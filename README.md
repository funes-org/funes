# Funes

Event sourcing for Ruby on Rails — append-only events as your source of truth, with flexible projections for reads.

## Event Sourcing?

Traditional Rails apps update state in place. You `update!` a record and the previous value is gone. Event sourcing takes a different approach: store *what happened* as immutable events, then derive current state by replaying them.

This gives you:

- **Complete audit trail** — every state change is recorded, forever
- **Temporal queries** — "what was the balance on December 1st?"
- **Multiple read models** — same events, different projections for different use cases
- **Safer refactoring** — rebuild any projection from the event log

## Installation

Add to your Gemfile:

```ruby
gem "funes"
```

Run the installation:

```bash
$ bin/bundle install
$ bin/rails generate funes:install
$ bin/rails db:migrate
```

## Three-Tier Consistency Model

Funes gives you fine-grained control over when and how projections run:

| Tier                      | When it runs                 | Use case                                        |
|:--------------------------|:-----------------------------|:------------------------------------------------|
| Consistency Projection    | Before event is persisted    | Validate business rules against resulting state |
| Transactional Projections | Same DB transaction as event | Critical read models needing strong consistency |
| Async Projections         | Background job (ActiveJob)   | Reports, analytics, non-critical read models    |

### Consistency Projection

Runs before the event is saved. If the resulting state is invalid, the event is rejected:

```ruby
class InventoryEventStream < Funes::EventStream
  consistency_projection InventorySnapshotProjection
end

class InventorySnapshot
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :quantity_on_hand, :integer, default: 0

  validates :quantity_on_hand, numericality: { greater_than_or_equal_to: 0 }
end
```

Now if someone tries to ship more than available:

```ruby

event = stream.append!(Inventory::ItemShipped.new(quantity: 9999))
event.valid? # => false
event.errors[:quantity_on_hand] # => ["must be greater than or equal to 0"]
```

The event is never persisted. Your invariants are protected.

### Transactional Projections

Update read models in the same database transaction. If anything fails, everything rolls back:

```ruby
add_transactional_projection InventoryLedgerProjection
```

### Async Projections

Schedule background jobs with full ActiveJob options:

```ruby
add_async_projection ReportingProjection, queue: :low, wait: 5.minutes
add_async_projection AnalyticsProjection, wait_until: Date.tomorrow.midnight
```

## Temporal Queries

Every event is timestamped. Query your stream at any point in time:

### Current state
```ruby
stream = InventoryEventStream.for("sku-12345")
stream.events # => all events
```

### State as of last month
```ruby
stream = InventoryEventStream.for("sku-12345", 1.month.ago)
stream.events # => events up to that timestamp
```

Projections receive the as_of parameter, so you can build point-in-time snapshots:

```ruby
# in your projection
interpretation_for(Inventory::ItemReceived) do |state, event, as_of|
  # as_of is available if you need temporal logic
  state.quantity_on_hand += event.quantity
  state
end
```

## Concurrency

Funes uses optimistic concurrency control. Each event in a stream gets an incrementing version number with a unique constraint on (idx, version).

If two processes try to append to the same stream simultaneously, one succeeds and the other gets a validation error — no locks, no blocking:

```ruby
event = stream.append!(SomeEvent.new)
unless event.valid?
  event.errors[:version] # => ["has already been taken"]
  # Reload and retry your business logic
end
```

## Testing

Funes provides helpers for testing projections in isolation:

```ruby
class InventorySnapshotProjectionTest < ActiveSupport::TestCase
  include Funes::ProjectionTestHelper

  test "receiving items increases quantity on hand" do
    initial_state = InventorySnapshot.new(quantity_on_hand: 10)
    event = Inventory::ItemReceived.new(quantity: 5, unit_cost: 9.99)

    result = interpret_event_based_on(InventorySnapshotProjection, event, initial_state)

    assert_equal 15, result.quantity_on_hand
  end
end
```

## Strict Mode

By default, projections ignore events they don't have interpretations for. Enable strict mode to catch missing handlers:

```ruby
class StrictProjection < Funes::Projection
  raise_on_unknown_events

  # Now forgetting to handle an event type raises Funes::UnknownEvent
end
```

## Documentation

API documentation is generated using [YARD](https://yardoc.org/). To generate and view the docs locally:

```bash
# Generate documentation
$ yard doc

# Start the documentation server
$ yard server
```

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
