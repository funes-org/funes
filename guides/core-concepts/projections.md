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

Projections follow a **functional approach**: each `interpretation_for` block receives the current state, applies the event's effects, and returns the updated state. State flows through as immutable snapshots being transformed, not mutated objects. This keeps projections predictable and easy to test.

## Virtual projections

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

When a new event is appended, Funes replays the stream through this projection and validates the result. If the resulting `OutstandingBalance` is invalid, the event is rejected.

## Persistent projections

Persistent projections extend `ActiveRecord` and are stored in your database. These are your read models — fast, queryable tables derived from the event history.

Their materialization table must follow a specific structure: no auto-incrementing primary key, and an `idx` string column as the primary key with a unique index. Use the provided generator to create a correctly structured migration:

```bash
$ bin/rails generate funes:materialization_table OutstandingBalance outstanding_balance:decimal last_payment_at:datetime
$ bin/rails db:migrate
```

Funes uses `upsert` on `idx` to keep the table in sync idempotently as new events arrive.

## Strict mode

By default, a projection silently ignores events it has no `interpretation_for`. If you want Funes to raise an error instead — useful for critical projections where a missing handler is a bug — enable strict mode:

```ruby
class OutstandingBalanceProjection < Funes::Projection
  raise_on_unknown_events

  # ...
end
```
