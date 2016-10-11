%% Copyright 2016, Bernard Notarianni
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

-module(barrel_http_replicate_SUITE).
-author("Bernard Notarianni").

%% API
-export(
   [ all/0
   , init_per_suite/1
   , end_per_suite/1
   , init_per_testcase/2
   , end_per_testcase/2
   ]).

-export(
   [ one_doc/1
   , target_not_empty/1
   , deleted_doc/1
   , random_activity/1
   ]).

all() ->
  [ one_doc
  , target_not_empty
  , deleted_doc
  , random_activity
  ].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(barrel_http),
  Config.

init_per_testcase(_, Config) ->
  ok = barrel_db:start(<<"testdb">>, barrel_test_rocksdb),
  ok = barrel_db:start(<<"source">>, barrel_source_rocksdb),
  {ok, HttpConn} = barrel_httpc:connect(source_url(), []),
  [{http_conn, HttpConn}|Config].

end_per_testcase(_, Config) ->
  ok = barrel_db:clean(<<"testdb">>),
  ok = barrel_db:clean(<<"source">>),
  HttpConn = proplists:get_value(http_conn, Config),
  stopped = barrel_httpc:stop(HttpConn),
  ok = barrel_replicate:clean(source(), target()),
  ok.

end_per_suite(Config) ->
  %% TODO this gives an error
  %% {error_db_destroy,
  %%     "IO error: lock testdb/LOCK: No locks available"}}}

  %% ok = erocksdb:destroy("testdb", []),
  %% ok = erocksdb:destroy("source", []),
  Config.

source_url() ->
  <<"http://localhost:8080/source">>.

source() ->
  {barrel_httpc, source_url()}.

target() ->
  <<"testdb">>.

one_doc(Config) ->
  HttpConn = proplists:get_value(http_conn, Config),
  {ok, Pid} = barrel_replicate:start_link(HttpConn, target()),
  Doc = #{ <<"_id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, RevId} = barrel_db:put(<<"source">>, <<"a">>, Doc, []),
  {1, [_]} = changes(<<"source">>, 0),
  {ok, _} = barrel_db:get(<<"source">>, <<"a">>, []),
  Doc2 = Doc#{<<"_rev">> => RevId},
  timer:sleep(200),
  {ok, Doc2} = barrel_db:get(<<"testdb">>, <<"a">>, []),
  stopped = barrel_replicate:stop(Pid),
  ok.

changes(DbId, Since) ->
  Fun = fun(Seq, DocInfo, _Doc, {_LastSeq, DocInfos}) ->
            {ok, {Seq, [DocInfo|DocInfos]}}
        end,
  barrel_db:changes_since(DbId, Since, Fun, {Since, []}).

target_not_empty(Config) ->
  HttpConn = proplists:get_value(http_conn, Config),
  Doc = #{ <<"_id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, RevId} = barrel_db:put(<<"source">>, <<"a">>, Doc, []),
  Doc2 = Doc#{<<"_rev">> => RevId},

  {ok, Pid} = barrel_replicate:start_link(HttpConn, target()),
  timer:sleep(200),

  {ok, Doc2} = barrel_db:get(<<"testdb">>, <<"a">>, []),
  stopped = barrel_replicate:stop(Pid),
  ok.

deleted_doc(Config) ->
  HttpConn = proplists:get_value(http_conn, Config),
  Doc = #{ <<"_id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, RevId} = barrel_db:put(<<"source">>, <<"a">>, Doc, []),

  {ok, Pid} = barrel_replicate:start_link(HttpConn, target()),
  barrel_db:delete(<<"source">>, <<"a">>, RevId, []),
  timer:sleep(200),
  {ok, Doc3} = barrel_db:get(<<"testdb">>, <<"a">>, []),

  %% TODO bug to be fixed
  %% https://gitlab.com/barrel-db/barrel-http/issues/1
  true = maps:get(<<"_deleted">>, Doc3),

  stopped = barrel_replicate:stop(Pid),
  ok.

random_activity(Config) ->
  HttpConn = proplists:get_value(http_conn, Config),
  Scenario = generate_scenario(),
  {ok, Pid} = barrel_replicate:start_link(HttpConn, target()),
  ExpectedResults = play_scenario(Scenario),
  timer:sleep(200),
  ok = check_all(ExpectedResults),
  stopped = barrel_replicate:stop(Pid),
  ok.

play_scenario(Scenario) ->
  Map = maps:new(),
  lists:foldl(fun(C, Acc) ->
                  play(C, Acc)
              end, Map, Scenario).

play({put, DocName, Value}, Map)->
  put_doc(DocName,Value),
  Map#{DocName => Value};
play({del, DocName}, Map) ->
  delete_doc(DocName),
  Map#{DocName => deleted}.

check_all(Map) ->
 Keys = maps:keys(Map),
  [ ok = check(K, Map) || K <- Keys ],
  ok.

check(DocName, Map) ->
  Id = list_to_binary(DocName),
  {ok, DocSource} = barrel_db:get(<<"source">>, Id, []),
  {ok, DocTarget} = barrel_db:get(<<"testdb">>, Id, []),
  case maps:get(DocName, Map) of
    deleted ->
      true = maps:get(<<"_deleted">>, DocSource),
      true = maps:get(<<"_deleted">>, DocTarget);
    Expected ->
      Expected = maps:get(<<"v">>, DocSource),
      Expected = maps:get(<<"v">>, DocTarget)
  end,
  ok.

put_doc(DocName, Value) ->
  Id = list_to_binary(DocName),
  case barrel_db:get(<<"source">>, Id, []) of
    {ok, Doc} ->
      Doc2 = Doc#{<<"v">> => Value},
      {ok,_,_} = barrel_db:put(<<"source">>, Id, Doc2, []);
    {error, not_found} ->
      Doc = #{<<"_id">> => Id, <<"v">> => Value},
      {ok,_,_} = barrel_db:put(<<"source">>, Id, Doc, [])
  end.

delete_doc(DocName) ->
  Id = list_to_binary(DocName),
  {ok, Doc} = barrel_db:get(<<"source">>, Id, []),
  RevId = maps:get(<<"_rev">>, Doc),
  barrel_db:delete(<<"source">>, Id, RevId, []).

generate_scenario() ->
  [ {put, "a", 1}
  , {put, "b", 1}
  , {put, "c", 1}
  , {put, "d", 1}
  , {put, "a", 2}
  , {put, "e", 1}
  , {put, "f", 1}
  , {put, "f", 2}
  , {del, "a"}
  , {put, "f", 3}
  ].
