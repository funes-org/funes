---
title: Building bi-temporal event streams
layout: default
parent: Recipes
nav_order: 7
---

# Building bi-temporal event streams
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Most systems treat time as something that happens *to* the data. Rows get updated, timestamps stick, and history shows up as a side effect at best. Event sourcing inverts that relationship: **time becomes a first-class dimension of the model**, queryable on its own terms. Audit trails stop being a separate ledger you maintain by hand. State reconstructions stop being painful archaeology. Debugging stops requiring a time machine you don't have. Once you can model *when* alongside *what*, whole categories of problems collapse into a single query. The architecture shifts with it. You model what *happened* instead of what *is*. The canonical store becomes an append-only log instead of a mutable table. Views of the system become queries over time, not snapshots cached in place.

Funes leans into this with full [**bitemporal**](https://martinfowler.com/articles/bitemporal-history.html) history. Every stream exposes two independent temporal dimensions. (Martin Fowler's article is the canonical reference if you want the conceptual background.)

| Dimension | Parameter | Stored in | Question it answers |
|:----------|:----------|:----------|:--------------------|
| Record history | `as_of` | `created_at` | "What did the system know at time T?" |
| Actual history | `at` | `occurred_at` | "What had actually happened by time T?" |

You can query each dimension on its own, or combine them.

## Record history

Funes stamps every event with `created_at` the moment it persists the event. Pass `as_of:` to `projected_with` to replay only the events the system knew about up to that point:

```ruby
stream = InventoryEventStream.for("sku-12345")
stream.projected_with(InventoryProjection) # current state
stream.projected_with(InventoryProjection, 
                      as_of: 1.month.ago) # state as the system knew it one month ago
```

This answers the question: *"If I had run this query on that date, what would I have seen?"*

## Actual history

You can record events retroactively. The moment the system learns about something is often not the moment it actually happened. The `occurred_at` column captures business time, independently of when the event entered the log.

You can set it explicitly on each append:

```ruby
stream.append(Salary::Raised.new(amount: 6500), at: Time.new(2025, 2, 15))
```

Or configure the stream to extract it automatically from an event attribute:

```ruby
class SalaryEventStream < Funes::EventStream
  actual_time_attribute :at
end

# The :at attribute value is used as occurred_at
stream.append(Salary::Raised.new(amount: 6500, at: Time.new(2025, 2, 15)))
```

When you configure neither `at:` nor `actual_time_attribute`, `occurred_at` defaults to `created_at`.

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

This is invaluable for audits, corrections, and compliance scenarios, where you need to reconstruct the exact state behind a decision.

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

The **state's temporal reference** flows into `initial_state` and `final_state` instead. That is what you passed as `at:` to `projected_with`. Funes calls these hooks once, before and after it replays the events. They are the right place for calculations relative to the query's point in time:

```ruby
final_state do |state, at|
  state.assign_attributes(days_in_effect: (at.to_date - state.since.to_date).to_i)
  state
end
```
