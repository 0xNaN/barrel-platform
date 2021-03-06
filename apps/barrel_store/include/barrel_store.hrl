
-define(DATA_DIR, "data").

-define(default_fold_options,
  #{
    start_key => nil,
    end_key => nil,
    gt => nil,
    gte => nil,
    lt => nil,
    lte => nil,
    max => 0,
    move => next
  }
).

-record(db, {
  name = <<>>,
  id = <<>>,
  conf = #{},
  pid = nil,
  store = nil,
  indexer = nil,
  indexer_mode = consistent,
  last_rid = 0,
  updated_seq = 0,
  indexed_seq = 0,
  docs_count = 0,
  system_docs_count = 0,
  deleted_count = 0,
  deleted = false
}).


%% db metadata
-define(DB_INFO, 1).

-define(DEFAULT_CHANGES_SIZE, 10).