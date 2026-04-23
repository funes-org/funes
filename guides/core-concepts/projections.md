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

> **Note:** If you need one row per version of the state rather than a single row per `idx`, see [Per-change Projections](per-change-projections).

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
