---
title: Temporal Queries
layout: default
nav_order: 6
---

# Temporal Queries
{: .no_toc }

After reading this guide, you will know how to query your event streams at any point in time — both by when events were recorded and by when they actually occurred.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Event sourcing preserves the full history of your system, which unlocks a class of questions that a mutable database simply cannot answer. Funes tracks two independent temporal dimensions, giving you full [**bitemporal**](https://martinfowler.com/articles/bitemporal-history.html) history:

| Dimension | Parameter | Stored in | Question it answers |
|:----------|:----------|:----------|:--------------------|
| Record history | `as_of` | `created_at` | "What did the system know at time T?" |
| Actual history | `at` | `occurred_at` | "What had actually happened by time T?" |

Each dimension can be queried independently or combined.

## Record history

Every event is stamped with `created_at` the moment it is persisted. Passing `as_of:` to `projected_with` replays only the events the system knew about up to that point:

```ruby
stream = InventoryEventStream.for("sku-12345")
stream.projected_with(InventoryProjection) # current state
stream.projected_with(InventoryProjection, 
                      as_of: 1.month.ago) # state as the system knew it one month ago
```

This answers the question: *"If I had run this query on that date, what would I have seen?"*

## Actual history

Events can be recorded retroactively — the moment the system learns about something may differ from when it actually happened. The `occurred_at` column captures business time, independently of when the event entered the log.

You can set it explicitly on each append:

```ruby
stream.append(Salary::Raised.new(amount: 6500), at: Time.new(2025, 2, 15))
```

Or configure the stream to extract it automatically from an event attribute:

```ruby
class SalaryEventStream < Funes::EventStream
  actual_time_attribute :at
end

# The :at attribute value is used as occurred_at automatically
stream.append(Salary::Raised.new(amount: 6500, at: Time.new(2025, 2, 15)))
```

When neither `at:` nor `actual_time_attribute` is configured, `occurred_at` defaults to `created_at`.

Query by actual history with `projected_with`:

```ruby
# Given everything the system knows now, what had actually happened by Feb 20?
stream = SalaryEventStream.for("sally-123")
stream.projected_with(SalaryProjection, at: Time.new(2025, 2, 20))
```

## Bitemporal queries

Combine both dimensions to ask: *"What did the system think had actually happened by time X, given only what it knew at time Y?"*

```ruby
# What did the system think Sally's salary was on Feb 20,
# given only what it knew as of Mar 1?
stream = SalaryEventStream.for("sally-123")
stream.projected_with(SalaryProjection, as_of: Time.new(2025, 3, 1), at: Time.new(2025, 2, 20))
```

This is invaluable for audits, corrections, and compliance scenarios where you need to reconstruct the exact state a decision was made from.

## Temporal context in projections

The temporal reference is not uniform across all interpretation hooks — it depends on which hook you are in.

Within `interpretation_for` blocks, `at` is the **event's `occurred_at`** — the business time at which that specific event took place. Use it to record effective dates directly from the event:

```ruby
interpretation_for Salary::Raised do |state, event, at|
  state.assign_attributes(current_amount: event.new_amount,
                          since: at)
  state
end
```

The **query's temporal reference** — what you passed as `at:` to `projected_with` — flows into `initial_state` and `final_state` instead. These hooks are called once, before and after all events are replayed, and are the right place for calculations relative to the query's point in time:

```ruby
final_state do |state, at|
  state.assign_attributes(days_in_effect: (at.to_date - state.since.to_date).to_i)
  state
end
```
