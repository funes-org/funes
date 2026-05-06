---
title: Projections
layout: default
parent: Core Concepts
nav_order: 2
---

# Projections
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

A **Projection** transforms a stream of events into a materialized representation — the state your application actually consumes.

## How projections work

A projection defines how each event type affects state. Funes replays the events in a stream through these handlers in order, producing a final state object.

You describe that logic using a declarative DSL built around `interpretation_for`. Projections follow a **functional approach**: each `interpretation_for` block receives the current state, applies the event's effects, and returns the updated state. This keeps projections predictable and easy to test.

## Materialization model

Every projection declares a **materialization model** — the class that represents the state being built. Funes instantiates it with a blank state, passes it through each `interpretation_for` block in sequence, and the final instance is the projection's output:

```ruby
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance
end
```

The materialization model can be either an `ActiveModel` class (for in-memory state) or an `ActiveRecord` model (for a persisted read table). The two projection types below each use a different kind.

### Virtual projections

Virtual projections extend `ActiveModel` and exist only in memory. They are calculated on the fly, which makes them ideal for validating business rules against the current state before an event is persisted.

```ruby
# app/projections/virtual_outstanding_balance_projection.rb
class OutstandingBalance
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :outstanding_balance, :decimal
  attribute :last_payment_at, :datetime

  validates :outstanding_balance, numericality: { greater_than_or_equal_to: 0 }
end

class VirtualOutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, event, _at|
    # apply issuance logic and return the updated state
  end

  interpretation_for Debt::PaymentReceived do |state, event, _at|
    # apply payment logic and return the updated state
  end
end
```

### Persistent projections

Persistent projections extend `ActiveRecord` and are stored in your database. These are your read models — fast, queryable tables derived from the event history.

Their materialization table must follow a specific structure: no auto-incrementing primary key, and an `idx` string column as the primary key with a unique index. Use the provided generator to create a correctly structured migration:

```bash
$ bin/rails generate funes:materialization_table OutstandingBalance outstanding_balance:decimal last_payment_at:datetime
$ bin/rails db:migrate
```

> Funes uses `upsert` on `idx` to keep the table in sync as new events arrive.

Once the migration is in place, define the ActiveRecord model and a projection that uses it:

```ruby
# app/models/outstanding_balance.rb
class OutstandingBalance < ApplicationRecord
  self.primary_key = "idx"
end
```

```ruby
# app/projections/outstanding_balance_projection.rb
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, event, _at|
    # apply issuance logic and return the updated state
  end

  interpretation_for Debt::PaymentReceived do |state, event, _at|
    # apply payment logic and return the updated state
  end
end
```

### Projections with custom persistence

Sometimes the right home for a projection isn't a database row. You might want to drop a JSON snapshot into S3, refresh a Redis cache, push a document to a search index, or call a third-party API. For these cases, Funes lets you replace the default upsert with any method on the materialization model.

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

A few things follow from this:

- **The materialization model no longer has to be ActiveRecord.** A plain `ActiveModel` class is enough, as long as it exposes `assign_attributes`, `attributes`, `valid?`, and `errors`. `OutstandingBalanceArchive` above isn't a database table — it's an in-memory shape that knows how to write itself somewhere.
- **Validation still runs first.** Funes calls `state.valid?` before delegating. If the state is invalid, Funes raises `Funes::InvalidMaterializationState` (with the failed materialization in `error.record`) and your persist method is never called. This keeps invalid data out of wherever the projection writes to, for the same reason it keeps invalid rows out of your database.
- **The method is expected to raise on failure.** Funes lets the exception propagate untouched. If your projection runs inside an `ActiveRecord::Base.transaction` (for example, from `append!`), the exception rolls back the transaction just like any other failure would.

Some places this fits naturally:

- **Object storage** (S3, GCS, Azure Blob): write a JSON, CSV, or Parquet snapshot keyed by `idx`. Useful when downstream consumers — analytics jobs, archival pipelines, data lakes — prefer files over rows.
- **Cache management** (Redis, Memcached): keep a denormalized read shape warm. Each event triggers a re-materialization that overwrites the cache entry on the same key, and consumers always read a current snapshot.
- **Search indexes** (Elasticsearch, Meilisearch, Algolia): push the projected document to the index after every relevant event so search results stay consistent with the event log.
- **External APIs and webhooks**: notify a third party when the projection's state changes, with the projected payload as the request body.

> **Note:** Re-running the projection with the same events should produce the same external state. The default upsert handles this naturally — the `idx`-keyed write is idempotent. When you supply your own persist method, you own that contract: write idempotently keyed on `idx` so re-runs (whether from job retries or from `projected_with` queries) don't double-apply.

> **Note:** When the projection is registered as `add_async_projection`, the persist method runs inside `Funes::PersistProjectionJob`. If the method raises, ActiveJob's standard retry machinery kicks in. Make sure the destination tolerates retries — most do, as long as the writes are idempotent on `idx`.

## Lifecycle hooks

Beyond `interpretation_for`, the DSL provides two hooks that bookend the replay.

`initial_state` is called once before any events are processed. It receives the materialization model class and the query's temporal reference, and must return the object that will be passed as `state` to the first interpretation:

```ruby
initial_state do |model, at|
  model.new(recorded_as_of: at)
end
```

`final_state` is called once after all events have been processed. It receives the accumulated state and the query's temporal reference, and must return the final state:

```ruby
final_state do |state, at|
  state.assign_attributes(days_in_effect: (at.to_date - state.since.to_date).to_i)
  state
end
```

> **Note:** The `at` parameter in both hooks is the **query's temporal reference** — what you passed as `at:` to `projected_with`. This is different from the `at` inside `interpretation_for` blocks, which is each event's own `occurred_at`. See the [Temporal Queries](../temporal-queries) guide for the full picture.

> **Note:** When `projected_with` has no events to replay — the stream is unknown, or the temporal filters exclude every event — it raises `ActiveRecord::RecordNotFound`, so controllers that use it get a 404 automatically. See [When there is nothing to project](../temporal-queries#when-there-is-nothing-to-project).

## Strict mode

By default, a projection silently ignores events it has no `interpretation_for`. If you want Funes to raise an error instead — useful for critical projections where a missing handler is a bug — enable strict mode:

```ruby
class OutstandingBalanceProjection < Funes::Projection
  raise_on_unknown_events
  # ...
end
```
