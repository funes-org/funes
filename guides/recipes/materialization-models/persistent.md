---
title: Persistent
layout: default
parent: Setting up projections
grand_parent: Recipes
nav_order: 2
---

# Persistent projections
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

A persistent materialization model writes the projected state somewhere consumers can query or access directly, without replaying events. Funes ships two flavors:

- **Database (default)** — an `ActiveRecord` row in a table that follows the framework's conventions, upserted on every relevant event.
- **Custom destination** — an `ActiveModel` that ships its attributes anywhere you like: S3, Redis, a search index, an external API, or any other store. You declare the method that sends it.

Both follow the same shape. Define a materialization model that exposes the methods Funes needs to drive it. Both `ActiveRecord::Base` and `ActiveModel::Model` already provide that API. Wire it to a projection, and let Funes do the rest. The only difference is where the state lands.

## Database (default)

The default persistent materialization model is an `ActiveRecord` row in a table that follows the framework's conventions. Funes upserts it on every relevant event, keyed by the stream's `idx`.

The framework convention for the shape of the table is simple. There is no auto-incrementing primary key. An `idx` string column takes that role, with a unique index behind it.

### Defining the projection's materialization model

Funes ships a generator that produces a migration already following the mentioned convention — pass a model name on its own:

```bash
$ bin/rails generate funes:materialization_table OutstandingBalance
```
or together with the columns you want:
```bash
$ bin/rails generate funes:materialization_table OutstandingBalance outstanding_balance:decimal last_payment_at:datetime
```

Either form scaffolds the `outstanding_balances` table with `idx` (string, primary key, unique-indexed), plus any columns you named. You need no extra tweaks to satisfy the convention.

Then declare the model inheriting from `ApplicationRecord` (Rails' usual `ActiveRecord::Base` subclass) and set the `idx` column as the primary key:

```ruby
# app/models/outstanding_balance.rb
class OutstandingBalance < ApplicationRecord
  self.primary_key = "idx"
end
```

That is everything Funes needs to handle the model: `ActiveRecord::Base` already exposes `attributes`, `assign_attributes`, `valid?`, and `errors`. Funes uses ActiveRecord's `upsert` to write the projected state into the table.

{: .note }
A bare `Model.upsert(...)` skips validations and callbacks entirely and goes straight to SQL. Funes does not. It calls `state.valid?` on the projected materialization first, and runs the upsert only when the state passes. This gate is particularly powerful when you wire the projection as **transactional** on an event stream. The upsert then runs inside the same transaction as the event insertion, so a failed `state.valid?` raises `Funes::InvalidMaterializationState` and rolls the whole append back. The event itself never lands in the log.

### Wiring the materialization model to the projection

Tell the projection which model to use when Funes materializes it:

```ruby
# app/projections/outstanding_balance_projection.rb
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  # Your interpretation blocks
end
```

Once Funes materializes the persistent projection, the row is a regular row in the database. Query it with the usual `where`, `find`, etc:

```ruby
OutstandingBalance.find("debts-123").outstanding_balance
```

Usually the table holds the latest known state. But you can replay the event stream whenever you need it. See how the state looked in the past, or project how it will look in the future. The event log will always be there for you.

### When to reach for it

- **Queryable read tables** — when consumers need to scan, sort, or filter projected state with familiar SQL. The default `ActiveRecord`-backed flavor gives you a regular table to query, with no extra plumbing.
- **Aggregations and joins** — pair the read table with the rest of your domain in the same database for joins, ad-hoc reports, and dashboards.

## Custom destination

Sometimes the database is the wrong home, and the projection materialization belongs in S3, Redis, a search index, or an external API. Replace the default upsert with a method you declare on the materialization model.

### Defining the projection's materialization model

The materialization model is a plain `ActiveModel` class that knows how to write itself to its destination. The class carries the persistence logic in a public method of your choice:

```ruby
# app/models/outstanding_balance_archive.rb
class OutstandingBalanceArchive
  include ActiveModel::Model
  include ActiveModel::Attributes
  
  # Your attributes and validation definitions 

  def upload_to_object_storage!
    S3_CLIENT.put_object(bucket: "balance-archives", 
                         key: "#{idx}.json", 
                         body: attributes.to_json)
  end
end
```

No migration, no row, no schema — the same `ActiveModel::Model` and `ActiveModel::Attributes` that drive [virtual projections](/recipes/materialization-models/virtual/) drive these too. The only addition is the persist method that ships the state to its destination.

{: .note }
When you supply your own persist method, you own the idempotency contract: write idempotently keyed on `idx` so re-runs don't double-apply.

### Wiring materialization model to the projection

Alongside `materialization_model`, declare the persist method with `persist_materialization_model_with`. Funes runs all interpretations, validates the resulting state, and then calls the method you named on the materialization instance:

```ruby
# app/projections/outstanding_balance_archive_projection.rb
class OutstandingBalanceArchiveProjection < Funes::Projection
  materialization_model OutstandingBalanceArchive
  persist_materialization_model_with :upload_to_object_storage!

  # Your interpretation blocks
end
```

A few things follow from this:

- **Validation still runs first.** Funes calls `state.valid?` before delegating. If the state is invalid, Funes raises `Funes::InvalidMaterializationState` (with the failed materialization in `error.record`) and never calls your persist method.
- **Your method must raise on failure.** Funes lets the exception propagate untouched. If the projection runs inside an `ActiveRecord::Base.transaction` (for example, from `append!`), the exception rolls back the transaction just like any other failure would.

{: .note }
When you register the projection with `add_async_projection`, the persist method runs inside `Funes::PersistProjectionJob`. If the method raises, ActiveJob's standard retry machinery takes over. Make sure the destination tolerates retries; most do, as long as the writes stay idempotent on `idx`.

### When to reach for it

The example above already showed the **object storage** case (S3, GCS, Azure Blob). It writes a JSON, CSV, or Parquet snapshot keyed by `idx`, for downstream consumers like analytics jobs, archival pipelines, or data lakes. The same shape covers other destinations just as well: define a persist method on the materialization model, then point the projection at it with `persist_materialization_model_with`.

- **Cache management** (Redis, Memcached) — keep a denormalized read shape warm so consumers always hit a current snapshot.
- **Search indexes** (Elasticsearch, Meilisearch, Algolia) — push the projected document to the index after every relevant event. Search results then stay consistent with the event log.
- **External APIs and webhooks** — notify a third party when the projection's state changes.

---

When the access pattern doesn't justify a stored representation at all, switch back to a [Virtual](/recipes/materialization-models/virtual/) materialization model — same API, no persistence.
