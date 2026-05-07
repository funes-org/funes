---
title: Having flexible persistent projections
layout: default
parent: Recipes
nav_order: 5
---

# Having flexible persistent projections
{: .no_toc }

After reading this guide, you will know how to use `persist_materialization_model_with` to send a projection's state anywhere — S3, Redis, a search index, an external API — instead of (or in addition to) a database row.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

The default Funes persistent projection writes its materialized state to an `ActiveRecord` table, keyed on `idx`. That covers most read models, but the right home for a projection isn't always a database row. You might want to drop a JSON snapshot into S3, refresh a Redis cache, push a document to a search index, or call a third-party API. For these cases, Funes lets you replace the default upsert with any method on the materialization model.

## Declaring the persist method

Declare the method with `persist_materialization_model_with`. Funes runs all the interpretations as usual, validates the resulting state, and then calls the method you named. The method takes no arguments — it operates on the materialization instance directly.

The materialization model carries the persistence logic. Below, `OutstandingBalanceArchive` is a plain `ActiveModel` class that knows how to write itself to S3:

```ruby
# app/models/outstanding_balance_archive.rb
class OutstandingBalanceArchive
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :idx, :string
  attribute :outstanding_balance, :decimal
  attribute :recorded_as_of, :datetime

  validates :outstanding_balance, numericality: { greater_than_or_equal_to: 0 }

  def upload_to_object_storage!
    S3_CLIENT.put_object(bucket: "balance-archives", key: "#{idx}.json", body: attributes.to_json)
  end
end
```

The projection points Funes at that method:

```ruby
# app/projections/outstanding_balance_archive_projection.rb
class OutstandingBalanceArchiveProjection < Funes::Projection
  materialization_model OutstandingBalanceArchive
  persist_materialization_model_with :upload_to_object_storage!

  interpretation_for Debt::Issued do |state, event, _at|
    # apply issuance logic and return the updated state
  end
end
```

## What this buys you

A few things follow from this:

- **The materialization model no longer has to be ActiveRecord.** A plain `ActiveModel` class is enough, as long as it exposes `assign_attributes`, `attributes`, `valid?`, and `errors`. `OutstandingBalanceArchive` above isn't a database table — it's an in-memory shape that knows how to write itself somewhere.
- **Validation still runs first.** Funes calls `state.valid?` before delegating. If the state is invalid, Funes raises `Funes::InvalidMaterializationState` (with the failed materialization in `error.record`) and your persist method is never called. This keeps invalid data out of wherever the projection writes to, for the same reason it keeps invalid rows out of your database.
- **The method is expected to raise on failure.** Funes lets the exception propagate untouched. If your projection runs inside an `ActiveRecord::Base.transaction` (for example, from `append!`), the exception rolls back the transaction just like any other failure would.

## Where this fits naturally

Some places this pattern earns its keep:

- **Object storage** (S3, GCS, Azure Blob): write a JSON, CSV, or Parquet snapshot keyed by `idx`. Useful when downstream consumers — analytics jobs, archival pipelines, data lakes — prefer files over rows.

   ```ruby
   def upload_to_object_storage!
     S3_CLIENT.put_object(bucket: "balance-archives",
                          key: "#{idx}.json",
                          body: attributes.to_json)
   end
   ```

- **Cache management** (Redis, Memcached): keep a denormalized read shape warm. Each event triggers a re-materialization that overwrites the cache entry on the same key, and consumers always read a current snapshot.

   ```ruby
   def refresh_cache!
     REDIS.set("outstanding_balance:#{idx}", attributes.to_json)
   end
   ```

- **Search indexes** (Elasticsearch, Meilisearch, Algolia): push the projected document to the index after every relevant event so search results stay consistent with the event log.

   ```ruby
   def index_document!
     SEARCH_CLIENT.index(index: "balances", id: idx, body: attributes)
   end
   ```

- **External APIs and webhooks**: notify a third party when the projection's state changes, with the projected payload as the request body.

   ```ruby
   def notify_partner!
     PARTNER_API.post("/balance-updates", json: attributes)
   end
   ```

> **Note:** Re-running the projection with the same events should produce the same external state. The default upsert handles this naturally — the `idx`-keyed write is idempotent. When you supply your own persist method, you own that contract: write idempotently keyed on `idx` so re-runs (whether from job retries or from `projected_with` queries) don't double-apply.

> **Note:** When the projection is registered as `add_async_projection`, the persist method runs inside `Funes::PersistProjectionJob`. If the method raises, ActiveJob's standard retry machinery kicks in. Make sure the destination tolerates retries — most do, as long as the writes are idempotent on `idx`.

To see how `persist_materialization_model_with` fits into the broader projection picture, check the [Projection](/concepts/projection/) concept.
