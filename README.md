# Funes

An event sourcing meta-framework designed to provide a frictionless experience for RoR developers to build and operate systems where history is as important as the present. Built with the one-person framework philosophy in mind, it honors the Rails doctrine by providing deep **conceptual compression** over what is usually a complex architectural pattern.

By distilling the mechanics of event sourcing into just three core concepts — **Events**, **Streams**, and **Projections** — Funes handles the underlying complexity of persistence and state reconstruction for you. It feels like the Rails you already know, giving you the power of a permanent source of truth with the same ease of use as a standard ActiveRecord model.

Unlike traditional event sourcing frameworks that require a total shift in how you build, Funes is designed for **progressive adoption**. It is a _"good neighbor"_ that coexists seamlessly with your existing ActiveRecord models and standard controllers. You can use Funes for a single mission-critical feature — like a single complex state machine — while keeping the rest of your app in "plain old Rails."

> [!WARNING]
> **Not Production Ready:** Funes is currently under active development and is not yet ready for production use. The API may change without notice, and features may be incomplete or unstable. Use at your own risk in development and testing environments only.

> Named after Funes the Memorious, the Borges character who could forget nothing, this framework embodies the principle that in some systems, remembering everything matters.

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
module Deposit
  class Created < Funes::Event
    attribute :value, :decimal
    attribute :effective_date, :date

    validates :value, presence: true, numericality: { greater_than: 0 }
    validates :effective_date, presence: true
  end

  class Withdrawn < Funes::Event
    attribute :amount, :decimal
    attribute :effective_date, :date

    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :effective_date, presence: true
  end
end
```

### Projections (the interpretations)

A **Projection** transforms events into a **materialized representation** — the state the application actually consumes.

* **Virtual projections:** these are extensions of `ActiveModel` and exist only in memory. They are calculated on-the-fly, making them ideal for "Consistency Projections" (see the consistency models bellow) used to validate business rules against the current state.
* **Persistent projections:** these are extensions of `ActiveRecord` and are stored in your database. These are your read nodels, allowing you to perform fast, standard Rails queries on data derived from your history.

**Note on architectural philosophy:** Projections in Funes follow a **functional programming approach** rather than object-oriented patterns. Each `interpretation_for` block is a pure transformation function that receives state, applies the event's effects, and returns the updated state. This approach ensures projections remain predictable, testable, and free from side effects. The state flows through interpretations as immutable snapshots being transformed, rather than objects being mutated.

```ruby
class DepositConsistency
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :original_value, :decimal
  attribute :balance, :decimal

  validates :original_value, presence: true, numericality: { greater_than: 0 }
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
end

class DepositConsistencyProjection < Funes::Projection
  materialization_model DepositConsistency

  interpretation_for Deposit::Created do |state, creation_event, _at|
    state.assign_attributes(original_value: creation_event.value, balance: creation_event.value)
    state
  end

  interpretation_for Deposit::Withdrawn do |state, withdrawn_event, _at|
    state.assign_attributes(balance: state.balance - withdrawn_event.amount)
    state
  end
end
```

#### Persistent Projection Materialization Tables

Persistent projections require as a **materialization model** an ActiveRecord model whose table follows a specific structure convention:

- **No auto-incrementing primary key** — use `id: false`
- **`idx` column as primary key** — string, not null
- **Unique index on `idx`** — required for upsert operations

Example migration:

```ruby
create_table :your_projections, id: false, primary_key: :idx do |t|
  t.string :idx, null: false
  # your domain columns here
end

add_index :your_projections, :idx, unique: true
```

The `idx` column links the read model to its event stream. Funes uses `upsert(attributes, unique_by: :idx)` for idempotent persistence.

You can generate a correctly structured migration using the provided generator:

```bash
$ bin/rails generate funes:materialization_table YourModel field:type field:type
```

### Event streams (the orchestrator)

An **Event Stream** is a logical grouping of events (e.g., all events for `Account:42`). It is the primary interface for your log and manages the lifecycle of a change.

* **Double validation:** it ensures an event is valid on its own (Unit) and that it doesn't violate business rules when applied to the current state (State/Consistency).
* **Consistency tiers:** the stream orchestrates how and when your projections (transactional or async) update.

```ruby
class DepositEventStream < Funes::EventStream
  consistency_projection DepositConsistencyProjection
  actual_time_attribute :effective_date
end

valid_event = Deposit::Created.new(value: 5_000, effective_date: Date.current)
DepositEventStream.for("deposit-123").append(valid_event)
valid_event.persisted? # => true

invalid_event = Deposit::Withdrawn.new(amount: 7_000, effective_date: Date.current)
DepositEventStream.for("deposit-123").append(invalid_event) # => led to negative balance invalid state
invalid_event.persisted? # => false
invalid_event.errors.empty? # => false
```

## Three-Tier Consistency Model

Funes gives you fine-grained control over when and how projections run:

| Tier                      | When it runs                 | Use case                                        |
|:--------------------------|:-----------------------------|:------------------------------------------------|
| Consistency Projection    | Before event is persisted    | Validate business rules against resulting state |
| Transactional Projections | Same DB transaction as event | Critical read models needing strong consistency |
| Async Projections         | Background job (ActiveJob)   | Reports, analytics, eventually consistent read models    |

### Consistency projections

* **Guard your invariants:** these run _before_ the event is saved to the log. If the resulting state (the "virtual projection") is invalid, the event is rejected and never persisted.
* **Business logic validation:** This is where you prevent "impossible" states, such as shipping more inventory than is available or overdrawing a bank account.

### Transactional projections

* **Atomic updates:** these update your persistent read models (`ActiveRecord`) within the same database transaction as the event.
* **Validation before persistence:** before upserting the materialization, Funes runs ActiveRecord validations on the materialization model. If the model is invalid, an `ActiveRecord::RecordInvalid` exception is raised, the transaction rolls back, and the event is not persisted.
* **Fail-loud on errors:** if a projection fails with a database error (e.g., constraint violation) or a validation error, the transaction rolls back, the event is marked as not persisted (`persisted?` returns `false`), and the exception (`ActiveRecord::StatementInvalid` or `ActiveRecord::RecordInvalid`) propagates. This ensures bugs are immediately visible rather than silently hidden, while keeping the event in a consistent state for any rescue logic in your application.

### Async projections

* **Background processing:** these are offloaded to `ActiveJob`, ensuring that heavy computations don't slow down the write path.
* **Native integration:** fully compliant with standard Rails job backends (`Sidekiq`, `Solid Queue`, etc.). You can pass standard `ActiveJob` options like `queue`, `wait`, or `wait_until`.
* **Temporal control (`temporal_context`):** customize the temporal reference passed to the projection. The resolved value becomes the `at` parameter received by interpretation blocks. Note that this is independent from the `at:` argument of `EventStream#append` — that value sets the event's `occurred_at` (business time) and does not flow through to async projections.
  * `:last_event_time` (Default): uses the **transaction time** (`created_at`) of the last event — i.e., when it was recorded in the database, not when the business event occurred (`occurred_at`).
  * `:job_time`: uses the current time when the job executes.
  * `Proc/Lambda`: allows for custom temporal logic (e.g., rounding to the `beginning_of_day`).

## Temporal queries

Funes supports two independent temporal dimensions, enabling full **bitemporal history**:

| Dimension | Parameter | Column | Question it answers |
|:----------|:----------|:-------|:--------------------|
| Record history | `as_of` | `created_at` | "What did the system know at time T?" |
| Actual history | `at` | `occurred_at` | "What had actually happened by time T?" |

### Record history (`as_of`)

Every event is timestamped with `created_at` when it is persisted. Query your stream at any point in record time by passing `as_of:` to `projected_with`:

```ruby
stream = InventoryEventStream.for("sku-12345")
stream.projected_with(InventoryProjection)             # current state (all known events)
stream.projected_with(InventoryProjection, as_of: 1.month.ago) # state as the system knew it 1 month ago
```

### Actual history (`at`)

Events can be recorded retroactively — the moment the system learns about something may differ from when it actually happened. The `occurred_at` column captures when the event actually occurred.

You can set actual time explicitly on append:

```ruby
stream.append(Salary::Raised.new(amount: 6500), at: Time.new(2025, 2, 15))
```

Or configure the stream to extract it from an event attribute automatically:

```ruby
class SalaryEventStream < Funes::EventStream
  actual_time_attribute :effective_date
end

# The :effective_date attribute value is used as occurred_at automatically
stream.append(Salary::Raised.new(amount: 6500, effective_date: Time.new(2025, 2, 15)))
```

When `at:` is not provided and no `actual_time_attribute` is configured, `occurred_at` defaults to the same value as `created_at`.

Query by actual history using `projected_with`:

```ruby
# "Given everything the system knows now, what had actually happened by Feb 20?"
stream = SalaryEventStream.for("sally-123")
stream.projected_with(SalaryProjection, at: Time.new(2025, 2, 20))
```

### Full bitemporal queries

Combine both dimensions to ask: "What did the system think had actually happened by time X, given only what it knew at time Y?"

```ruby
# What did the system think Sally's salary was on Feb 20, given only what it knew as of Mar 1?
stream = SalaryEventStream.for("sally-123")
stream.projected_with(SalaryProjection, as_of: Time.new(2025, 3, 1), at: Time.new(2025, 2, 20))
```

### Temporal reference in projections

Projections' interpretation blocks receive `at` as their third parameter — the temporal reference used when projecting:

```ruby
interpretation_for(Deposit::Created) do |state, event, at|
  state.assign_attributes(original_value: event.value,
                          balance: event.value,
                          created_at: at)
  state
end
```

## Event Metainformation

In auditable systems, knowing *what* happened is only part of the story — you also need to know *who* did it and *in what context*. Event metainformation allows you to attach contextual data to every event recorded during a request, such as the acting user, the controller action, or the application version. This enriches your audit trail with the provenance information required for compliance, debugging, and forensic analysis.

Configure the attributes your application needs via an initializer:

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [:user_id, :action, :git_version]
end
```

For complete setup instructions, validation configuration, and usage examples, see [Event Metainformation Documentation](EVENT_METAINFORMATION.md).

## Optimistic concurrency control

Funes uses optimistic concurrency control. Each event in a stream gets an incrementing version number with a unique constraint on (idx, version).

If two processes try to append to the same stream simultaneously, one succeeds and the other gets a validation error — no locks, no blocking.

## Documentation

Full API documentation is available at [docs.funes.org](https://docs.funes.org).

> **Note:** Until a production-ready version is released, only the latest version is documented. Versioned documentation will be introduced once the API stabilizes.

## Strict mode

By default, projections ignore events they don't have interpretations for. By using `raise_on_unknown_events` you enable strict mode to catch missing handlers. This is specially worth for critical projections.

## Compatibility

- **Ruby:** 3.1, 3.2, 3.3, 3.4
- **Rails:** 7.1, 7.2, 8.0, 8.1

Rails 8.0+ requires Ruby 3.2 or higher.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
