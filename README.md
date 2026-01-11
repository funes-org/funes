# Funes

An event sourcing meta-framework designed to provide a frictionless experience for RoR developers to build and operate systems where history is as important as the present. Built with the one-person framework philosophy in mind, it honors the Rails doctrine by providing deep **conceptual compression** over what is usually a complex architectural pattern.

By distilling the mechanics of event sourcing into just three core concepts — **Events**, **Streams**, and **Projections** — Funes handles the underlying complexity of persistence and state reconstruction for you. It feels like the Rails you already know, giving you the power of a permanent source of truth with the same ease of use as a standard ActiveRecord model.

Unlike traditional event sourcing frameworks that require a total shift in how you build, Funes is designed for **progressive adoption**. It is a _"good neighbor"_ that coexists seamlessly with your existing ActiveRecord models and standard controllers. You can use Funes for a single mission-critical feature — like a single complex state machine — while keeping the rest of your app in "plain old Rails."

## Event Sourcing?

In a typical Rails app, data has no past — only a present. You `update!` a record and the previous value is gone. Event sourcing takes a different approach: store *what happened* as immutable events, then derive current state by replaying them.

This gives you:

- **Complete audit trail** — every state change is recorded, _forever_
- **Temporal queries** — "what was the balance on December 1st?"
- **Multiple read models** — same events, different (decoupled!) projections for different use cases
- **Safer refactoring** — rebuild any projection from the event log

Event sourcing is a reasonable choice for complex, trackable state machines and for systems where state depends on the observer's moment in time — financial systems, compliance workflows, or anywhere historical data integrity and context are non-negotiable.

> It’s the right choice for any application where "what was true then?" matters as much as "what is true now?"

## Installation

Add to your Gemfile:

```ruby
gem "funes-rails"
```

Run the installation:

```bash
$ bin/bundle install
$ bin/rails generate funes:install
$ bin/rails db:migrate
```

## Core concepts

Funes bridges the gap between event sourcing theory and the Rails tools you already know (`ActiveModel`, `ActiveRecord`, `ActiveJob`).

![core concepts](https://raw.github.com/funes-org/funes/main/concepts.png)

### Events (the facts)

An **Event** is an immutable representation of a fact. Unlike a traditional model, an event is not "current state" — it is a record of history.

* **Fact _vs_ state:** while a `User` model represents who they are now, a `User::Registered` event represents what happened.
* **No schema impedance:** events are not `ActiveRecord` models; they are a kind of `ActiveModel` instances. This prevents "migration fatigue", as your historical facts never need to change their schema just because your UI requirements did.
* **Built-in validation:** since events behaves similarly to `ActiveModel`, they carry their own internal validation rules (e.g., ensuring a quantity is present).

```ruby
module Debt
  class Issued < Funes::Event
    attribute :amount, :decimal
    attribute :interest_rate, :decimal
    attribute :at, :datetime

    validates_presence_of :at
    validates :amount, numericality: { greater_than: 0 }
    validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }
  end

  class PaymentReceived < Funes::Event
    attribute :principal_amount, :decimal
    attribute :interest_amount, :decimal
    attribute :at, :datetime

    validates_presence_of :at
    validates :principal_amount, numericality: { greater_than_or_equal_to: 0 }
    validates :interest_amount, numericality: { greater_than_or_equal_to: 0 }
  end
end
```

### Projections (the interpretations)

A **Projection** transforms events into a **materialized representation** — the state the application actually consumes.

* **Virtual projections:** these are extensions of `ActiveModel` and exist only in memory. They are calculated on-the-fly, making them ideal for "Consistency Projections" (see the consistency models bellow) used to validate business rules against the current state.
* **Persistent projections:** these are extensions of `ActiveRecord` and are stored in your database. These are your read nodels, allowing you to perform fast, standard Rails queries on data derived from your history.

**Note on architectural philosophy:** Projections in Funes follow a **functional programming approach** rather than object-oriented patterns. Each `interpretation_for` block is a pure transformation function that receives state, applies the event's effects, and returns the updated state. This approach ensures projections remain predictable, testable, and free from side effects. The state flows through interpretations as immutable snapshots being transformed, rather than objects being mutated.

```ruby
class OutstandingBalance
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :outstanding_balance, :decimal
  attribute :last_payment_at, :datetime

  validates :outstanding_balance, numericality: { greater_than_or_equal_to: 0 }
end

class VirtualOutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, issuance_event, as_of|
    # your logic here to handle the interest curve, update and return the state
  end

  interpretation_for Debt::PaymentReceived do |state, payment_event|
    # your logic here to handle the payment effects to update and return the state
  end
end
```

### Event streams (the orchestrator)

An **Event Stream** is a logical grouping of events (e.g., all events for `Account:42`). It is the primary interface for your log and manages the lifecycle of a change.

* **Double validation:** it ensures an event is valid on its own (Unit) and that it doesn't violate business rules when applied to the current state (State/Consistency).
* **Consistency tiers:** the stream orchestrates how and when your projections (transactional or async) update.

```ruby
class DebtEventStream < Funes::EventStream
  consistency_projection VirtualOutstandingBalanceProjection
end

valid_event = Debt::Issued.new(amount: 100, interest_rate: 0.05, at: Time.current)
DebtEventStream.for("debts-identifier").append(valid_event)
valid_event.errors.empty? # => true

invalid_event = Debt::PaymentReceived.new(principal_amount: 100, interest_amount: 50, at: valid_event.at)
DebtEventStream.for("debts-identifier").append(invalid_event) # => led to overpayment invalid state
invalid_event.errors.empty? # => false
```

## Three-Tier Consistency Model

Funes gives you fine-grained control over when and how projections run:

| Tier                      | When it runs                 | Use case                                        |
|:--------------------------|:-----------------------------|:------------------------------------------------|
| Consistency Projection    | Before event is persisted    | Validate business rules against resulting state |
| Transactional Projections | Same DB transaction as event | Critical read models needing strong consistency |
| Async Projections         | Background job (ActiveJob)   | Reports, analytics, non-critical read models    |

### Consistency projections

* **Guard your invariants:** these run _before_ the event is saved to the log. If the resulting state (the "virtual projection") is invalid, the event is rejected and never persisted.
* **Business logic validation:** This is where you prevent "impossible" states, such as shipping more inventory than is available or overdrawing a bank account.

### Transactional projections

* **Atomic updates:** these update your persistent read models (`ActiveRecord`) within the same database transaction as the event.
* **Strong consistency:** if the projection fails to update, the entire transaction rolls back. This ensures your critical read models are always in sync with the event log.

### Async projections

* **Background processing:** these are offloaded to `ActiveJob`, ensuring that heavy computations don't slow down the write path.
* **Native integration:** fully compliant with standard Rails job backends (`Sidekiq`, `Solid Queue`, etc.). You can pass standard `ActiveJob` options like `queue`, `wait`, or `wait_until`.
* **Temporal control (`as_of`):** customize the point-in-time reference for the projection:
  * `:last_event_time` (Default): uses the creation time of the last event.
  * `:job_time`: uses the current time when the job actually executes.
  * `Proc/Lambda`: allows for custom temporal logic (e.g., rounding to the `beginning_of_day`).

## Temporal queries

Every event is timestamped. Query your stream at any point in time:

```ruby
InventoryEventStream.for("sku-12345") # => returns an instance of it with the current state
InventoryEventStream.for("sku-12345", 1.month.ago) # => returns an instance of it with the state of 1 month ago
```

Projections' interpretations receive the `as_of` parameter, so you can build logical point-in-time snapshots:

```ruby
interpretation_for(Debt::Issued) do |state, event, as_of|
  present_value = event.amount * (1 + event.interest_rate) ** periods_between(event.at, as_of)
  state.assign_attributes(present_value:)
  state
end
```

## Optimistic concurrency control

Funes uses optimistic concurrency control. Each event in a stream gets an incrementing version number with a unique constraint on (idx, version).

If two processes try to append to the same stream simultaneously, one succeeds and the other gets a validation error — no locks, no blocking.

## Strict mode

By default, projections ignore events they don't have interpretations for. By using `raise_on_unknown_events` you enable strict mode to catch missing handlers. This is specially worth for critical projections.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
