---
title: Atomic writes
layout: default
parent: Recipes
nav_order: 5
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

- `append` returns the event itself and quietly leaves it invalid (`event.persisted? == false`, `event.errors.any?`) when validation fails. Your controller checks `persisted?` and re-renders.
- `append!` also returns the event, but raises `ActiveRecord::RecordInvalid` on any failure. Inside a transaction you opened, that exception rolls back everything in the block — exactly the behaviour you want when the event has to commit alongside other state.

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

## Appending to two streams atomically

When a single business action produces events on more than one stream, wrap both appends in the same `ActiveRecord::Base.transaction` so they either both commit or neither does:

```ruby
event_1 = Order::Placed.new(total: 99.99)
event_2 = Inventory::ItemReserved.new(sku: "ABC", quantity: 1)
begin
  ActiveRecord::Base.transaction do
    OrderEventStream.for(order_id).append!(event_1)
    InventoryEventStream.for(sku).append!(event_2)
  end
rescue ActiveRecord::RecordInvalid
  event_1.persisted? # => false
  event_2.persisted? # => false
end
```

If either append fails — for any reason — the exception rolls the whole transaction back. Neither event lands in its log, and both stay queryable after the rescue just like an event that failed a single-stream `append!`. This is how you keep multi-stream operations consistent without inventing a saga, a distributed-transaction layer, or an outbox.

## Async projections wait for commit

Async projections behave the same way regardless of which form of append you call. Whether `append` is opening its own transaction or `append!` is running inside one your code controls, jobs are only enqueued once the outermost transaction commits. The guarantee comes from Rails' [`enqueue_after_transaction_commit`](https://edgeapi.rubyonrails.org/classes/ActiveJob/Enqueuing.html#method-c-enqueue_after_transaction_commit); when the transaction rolls back, the deferred enqueue is discarded, so no job ever runs against an event that never landed.
