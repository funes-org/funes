---
title: Persistent
layout: default
parent: Setting up materialization models
grand_parent: Recipes
nav_order: 2
---

# Persistent materialization models
{: .no_toc }

After reading this guide, you will know how to set up a persistent materialization model — either backed by an `ActiveRecord` row in a Funes-shaped database table (the default), or written to any custom destination by supplying your own persistence method.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

A persistent materialization model is written somewhere durable so it can be queried directly without replaying the events. Funes ships two flavors:

- **Database (default)** — an `ActiveRecord` row in a Funes-shaped table, upserted on every relevant event.
- **Custom destination** — an `ActiveModel` shipped to S3, Redis, a search index, an external API, or any other store, via your own persistence method.

## Database (default)

The default persistent materialization model is an `ActiveRecord` row in a Funes-shaped table. Every relevant event triggers an upsert keyed by the stream's `idx`, so the row stays in sync with the latest projected state without you writing any persistence code.

### Generating the migration

The persistent table must follow a specific structure: no auto-incrementing primary key, and an `idx` string column as the primary key with a unique index. The provided generator builds it correctly:

```bash
$ bin/rails generate funes:materialization_table OutstandingBalance outstanding_balance:decimal last_payment_at:datetime
$ bin/rails db:migrate
```

This creates a migration for an `outstanding_balances` table with `idx` (string, primary key) plus the columns you named.

### Defining the model

Tell ActiveRecord that `idx` is the primary key:

```ruby
# app/models/outstanding_balance.rb
class OutstandingBalance < ApplicationRecord
  self.primary_key = "idx"
end
```

Validations on the model run against the projected state before the upsert happens, so invalid states never reach the table.

### Wiring it to a projection

Point a projection at the model and Funes handles the rest:

```ruby
# app/projections/outstanding_balance_projection.rb
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, event, _at|
    state.outstanding_balance = event.amount
    state
  end

  interpretation_for Debt::PaymentReceived do |state, event, at|
    state.outstanding_balance -= event.principal_amount
    state.last_payment_at = at
    state
  end
end
```

> Funes uses `upsert` on `idx` to keep the table in sync as new events arrive.

### Querying the read model

Once persisted, the row is a regular ActiveRecord row — query it with the usual `where`, `find_by`, and scopes:

```ruby
OutstandingBalance.find_by(idx: "debts-123").outstanding_balance
```

If you need to read the projection at a specific point in time, use `projected_with(at:)` instead of querying the table directly — the table holds *latest known state*, while `projected_with` can reconstruct historical state from the event log.

When the database is the wrong home for a projection, see [Custom destinations](#custom-destinations) below.

## Custom destinations

When you'd rather send the projected state to S3, Redis, a search index, an external API, or any other store, replace the default upsert with any method on the materialization model.

### Declaring the persist method

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

### What this buys you

A few things follow from this:

- **The materialization model no longer has to be ActiveRecord.** A plain `ActiveModel` class is enough, as long as it exposes `assign_attributes`, `attributes`, `valid?`, and `errors`.
- **Validation still runs first.** Funes calls `state.valid?` before delegating. If the state is invalid, Funes raises `Funes::InvalidMaterializationState` (with the failed materialization in `error.record`) and your persist method is never called.
- **The method is expected to raise on failure.** Funes lets the exception propagate untouched. If your projection runs inside an `ActiveRecord::Base.transaction` (for example, from `append!`), the exception rolls back the transaction just like any other failure would.

### Where this fits naturally

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

{: .note }
Re-running the projection with the same events should produce the same external state. The default upsert handles this naturally — the `idx`-keyed write is idempotent. When you supply your own persist method, you own that contract: write idempotently keyed on `idx` so re-runs (whether from job retries or from `projected_with` queries) don't double-apply.

{: .note }
When the projection is registered as `add_async_projection`, the persist method runs inside `Funes::PersistProjectionJob`. If the method raises, ActiveJob's standard retry machinery kicks in. Make sure the destination tolerates retries — most do, as long as the writes are idempotent on `idx`.
