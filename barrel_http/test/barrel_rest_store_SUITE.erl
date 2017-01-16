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

-module(barrel_rest_store_SUITE).

-export([
  all/0,
  end_per_suite/1,
  init_per_suite/1
]).

-export([
    accept_get/1
  , reject_unknown_store/1
]).

all() ->
  [
    accept_get
    , reject_unknown_store
  ].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(barrel_http),
  {ok, _} = application:ensure_all_started(barrel),
  _ = barrel_store:create_db(<<"testdb">>, #{}),
  Config.

end_per_suite(Config) ->
  application:stop(barrel),
  _ = (catch rocksdb:destroy("docs", [])),
  Config.

accept_get(_Config) ->
  {200, R1} = test_lib:req(get, "/testdb"),
  Info = jsx:decode(R1, [return_maps]),
  
  #{<<"name">> := _,
    <<"id">> := _,
    <<"docs_count">> := _,
    <<"last_update_seq">> := _,
    <<"system_docs_count">> := _,
    <<"last_index_seq">> := _} = Info,
  ok.

reject_unknown_store(_Config) ->
  {404, _} = test_lib:req(get, "/badstore"),
  ok.

