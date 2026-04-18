# Funes

An event sourcing meta-framework designed to provide a frictionless experience for RoR developers to build and operate systems where history is as important as the present. Built with the one-person framework philosophy in mind, it honors the Rails doctrine by providing deep **conceptual compression** over what is usually a complex architectural pattern.

At its core is a declarative DSL that favors the **interpretation of events** over all the plumbing. You describe how each event affects state, and Funes handles persistence, ordering, concurrency, and materialization for you.

By distilling the mechanics of event sourcing into just three core concepts — **Events**, **Streams**, and **Projections** — Funes handles the underlying complexity of persistence and state reconstruction for you. It feels like the Rails you already know, giving you the power of a permanent source of truth with the same ease of use as a standard ActiveRecord model.

Unlike traditional event sourcing frameworks that require a total shift in how you build, Funes is designed for **progressive adoption**. It is a _"good neighbor"_ that coexists seamlessly with your existing ActiveRecord models and standard controllers. You can use Funes for a single mission-critical feature — like a single complex state machine — while keeping the rest of your app in "plain old Rails."

> Named after Funes the Memorious, the Borges character who could forget nothing, this framework embodies the principle that in some systems, remembering everything matters.

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

- **Events** — immutable `ActiveModel` objects that record what happened, with built-in validation and no schema migrations
- **Projections** — transform a stream of events into a materialized state, either in-memory (`ActiveModel`) or persisted (`ActiveRecord`)
- **Event Streams** — orchestrate writes, run double validation, and control when projections update (synchronously or via `ActiveJob`)

For a full walkthrough of each concept, see the [guides](https://docs.funes.org).

## The DSL

At the heart of Funes is a declarative DSL designed so you spend your time on what matters — *interpreting events* — not on the plumbing that surrounds them.

A projection reads like a description of your domain logic:

```ruby
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, event, _at|
    state.assign_attributes(outstanding_balance: event.amount)
    state
  end

  interpretation_for Debt::PaymentReceived do |state, event, _at|
    state.outstanding_balance -= event.principal_amount
    state.last_payment_at = event.at
    state
  end
end
```

There is no event-store wiring, no manual replay loop, no serializer configuration. You declare how each event affects state, and Funes takes care of persistence, ordering, concurrency, and materialization. The same DSL scales from a single in-memory validation to a fully persisted read model.

## Optimistic concurrency control

Funes uses optimistic concurrency control. Each event in a stream gets an incrementing version number with a unique constraint on (idx, version).

If two processes try to append to the same stream simultaneously, one succeeds and the other gets a validation error — no locks, no blocking.

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

## Documentation

Guides and full API documentation are available at [docs.funes.org](https://docs.funes.org).

## Compatibility

- **Ruby:** 3.1+
- **Rails:** 7.1+

Rails 8.0+ requires Ruby 3.2 or higher.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
