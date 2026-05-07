---
title: Event Stream
layout: default
parent: Concepts
nav_order: 2
---

# Event Stream
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

An **Event Stream** is a sequenced group of events from the event log, identified by a stream ID. In practice, a stream usually represents a single entity instance — `Account:42`, `Order:99` — but it can just as well group a broader collection. Either way, the stream is the primary interface for writing to the log and orchestrating how projections update.

## Appending events

You define a stream by inheriting from `Funes::EventStream`, then use `.for` to get the stream for a specific entity and `.append` to record an event:

```ruby
# app/event_streams/debt_event_stream.rb
class DebtEventStream < Funes::EventStream; end
DebtEventStream.for("debts-123").append(Debt::Issued.new(amount: 100, interest_rate: 0.05, at: Time.current))
```

The string passed to `.for` is the stream identifier (`idx`). It links all events for that entity together and ties them to their read models.

You don't need to create a stream before using it. If no events have been recorded for a given `idx`, the stream is implicitly created the moment the first event is appended. There is no setup step — `DebtEventStream.for("debts-456")` works whether `"debts-456"` has a hundred events or none at all.

## Double validation

Before an event is persisted, the stream runs two validation passes:

1. **Unit validation** — is the event itself valid? (`ActiveModel` validations on the event class)
2. **Consistency validation** — does the event produce a valid state? (the consistency projection)

Only if both pass does the event get written to the log.

## Consistency projections

A consistency projection is a virtual projection that runs before the event is saved. If the resulting state is invalid, the event is rejected:

```ruby
class DebtEventStream < Funes::EventStream
  consistency_projection VirtualOutstandingBalanceProjection
end

# This payment would overdraw the balance — the stream rejects it
invalid_event = Debt::PaymentReceived.new(principal_amount: 999_999, interest_amount: 0, at: Time.current)
DebtEventStream.for("debts-123").append(invalid_event)

invalid_event.persisted?    # => false
invalid_event.errors.any?   # => true
```

## Consistency tiers

Beyond the consistency projection, the stream gives you fine-grained control over when other projections run:

| Tier | When it runs | Use case |
|:-----|:-------------|:---------|
| Consistency Projection | Before the event is persisted | Validate business rules against the resulting state |
| Transactional Projections | Same DB transaction as the event | Read models needing strong consistency |
| Async Projections | Background job via `ActiveJob` | Reports, analytics, eventually consistent read models |

Transactional projections roll back together with the event if anything fails, keeping your data consistent. Async projections are offloaded to your job backend — `Sidekiq`, `Solid Queue`, or any other `ActiveJob`-compatible adapter.

## Host-managed transactions

When you need to coordinate an `append` with other writes inside a transaction your code already controls, use `append!`. See the [Atomic writes](/recipes/atomic-writes/) recipe for the full pattern.
