---
title: Atomic writes
layout: default
parent: Recipes
nav_order: 1
---

# Atomic writes
{: .no_toc }

After reading this guide, you will know when to reach for `append!` instead of `append`, and how to use it to keep an event in lockstep with other writes inside a transaction your code already controls.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

By default, `append` opens its own transaction so the event, its consistency projection, and any transactional projections all commit or roll back together. That's the right behaviour most of the time. But sometimes you need to coordinate the append with writes outside the stream — keep a sibling `update!` in lockstep, or write to two streams atomically. For those cases, Funes ships `append!`.

## `append` vs `append!`

The pair mirrors Rails' `save` / `save!`:

- `append` returns the stream and quietly leaves the event invalid (`event.persisted? == false`, `event.errors.any?`) when validation fails. Your controller checks `persisted?` and re-renders.
- `append!` raises `ActiveRecord::RecordInvalid` on any failure. Inside a transaction you opened, that exception rolls back everything in the block — exactly the behaviour you want when the event has to commit alongside other state.

## Coordinating with sibling writes

Wrap the append and the sibling write in a single `ActiveRecord::Base.transaction`:

```ruby
event = Order::Placed.new(total: 99.99)
begin
  ActiveRecord::Base.transaction do
    customer.update!(last_ordered_at: Time.current)
    OrderEventStream.for(order_id).append!(event)
  end
rescue ActiveRecord::RecordInvalid
  event.persisted?  # => false
  event.errors.any? # => true
end
```

If the event is invalid — its own validations fail, the consistency projection rejects it, or any transactional projection raises — the customer update rolls back too. The failed event stays queryable after the rescue (`persisted?`, `errors`), just like a record that failed `save!`.

Async projections behave correctly here as well: they're only enqueued once the outer transaction commits, so a rolled-back transaction never schedules a job.

> **Note:** Use `append` when the stream owns the transaction, and `append!` when your code does. Mixing the two inside a single host-managed block defeats the rollback guarantees `append!` provides.
