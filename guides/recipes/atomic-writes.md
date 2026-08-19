---
title: Atomic writes
layout: default
parent: Recipes
nav_order: 5
---

# Atomic writes
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

By default, `append` opens its own transaction, so the event and any transactional projections commit or roll back together. (The consistency projection needs no transaction: it runs before the event reaches the database and writes nothing.) That's the right behaviour most of the time. But sometimes you need to coordinate the append with writes outside the stream — keep a sibling `update!` in lockstep, or write to two streams atomically. For those cases, Funes ships `append!`.

## `append` vs `append!`

The pair mirrors Rails' `save` / `save!`:

- `append` returns the event itself and quietly leaves it invalid (`event.persisted? == false`, `event.errors.any?`) when the event fails its own validations or the consistency projection rejects it. Your controller checks `persisted?` and re-renders.
- `append!` also returns the event, but raises `ActiveRecord::RecordInvalid` on the failures that `append` leaves quiet. Inside a transaction you opened, that exception rolls back everything in the block — exactly the behaviour you want when the event has to commit alongside other state.

{: .note }
The quiet path of `append` covers the event's own validations and the consistency projection only. When a transactional projection fails, both forms raise — see [Rescue transactional projection failures](/recipes/events-the-rails-way/controllers/#rescue-transactional-projection-failures).

## Coordinate with sibling writes

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

If the event fails its own validations, or the consistency projection rejects it, `append!` raises `ActiveRecord::RecordInvalid` and the customer update rolls back too. The failed event stays queryable after the rescue (`persisted?`, `errors`), just like a model that failed `save!`. A transactional projection failure also rolls back the whole block, but through its own exceptions, and it puts no errors on the event — see [Rescue transactional projection failures](/recipes/events-the-rails-way/controllers/#rescue-transactional-projection-failures).

## Append to two streams atomically

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

If either append fails — for any reason — the exception rolls the whole transaction back. Neither event lands in its log, and both stay queryable after the rescue just like an event that failed a single-stream `append!`. This is how you keep multi-stream operations consistent without a saga, a distributed-transaction layer, or an outbox.

## Async projections wait for commit

Async projections behave the same way regardless of which form of append you call. Whether `append` opens its own transaction or `append!` runs inside one your code controls, Funes enqueues jobs only after the outermost transaction commits. The guarantee comes from Rails' [`enqueue_after_transaction_commit`](https://edgeapi.rubyonrails.org/classes/ActiveJob/Enqueuing.html#method-c-enqueue_after_transaction_commit); when the transaction rolls back, Rails discards the deferred enqueue, so no job ever runs against an event that never landed.
