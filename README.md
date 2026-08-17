# Funes

[![Gem Version](https://badge.fury.io/rb/funes-rails.svg)](https://badge.fury.io/rb/funes-rails)

Funes is an event sourcing meta-framework for Ruby on Rails. It helps you build and operate systems where history matters as much as the present.

It follows the one-person framework philosophy and honors the Rails doctrine with deep **conceptual compression** over a domain that is hard to keep under control.

A declarative, functional-flavored DSL sits at the core of Funes. The DSL favors the **interpretation of events** over the plumbing. You describe how each event affects state. Funes then handles persistence, ordering, concurrency, and materialization.

Funes distills the mechanics of event sourcing into three core concepts: **Events**, **Event Streams**, and **Projections**. It handles the complexity of persistence and state reconstruction for you. The result feels like the Rails you already know.

It does not require a total shift in how you build your application. The meta-framework actually encourages **progressive adoption** and is a _"good neighbor"_ to "plain old Rails". Funes coexists gracefully with the Rails primitives you already have in place. You can use Funes for one mission-critical feature and keep the other parts untouched.

> [!TIP]
> The name comes from "Funes the Memorious," the Borges character who could forget nothing. He and the meta-framework share that trait — what is a curse to the former is a blessing to the latter.

## Installation

Add the gem to your Gemfile:

```ruby
gem "funes-rails"
```

Then run these commands:

```bash
$ bin/bundle install
$ bin/rails generate funes:install
$ bin/rails db:migrate
```

## Core concepts

Funes bridges the gap between event sourcing theory and the Rails tools you already know (`ActiveModel`, `ActiveRecord`, `ActiveJob`).

```text
 ┌────────────────────┐                      ┌──────────────────────┐
 │       Event        │ ─── appended to ───▶ │     EventStream      │
 └────────────────────┘                      └──────────────────────┘
  < Funes::Event                              < Funes::EventStream
  < ActiveModel::Model                                  │
                                                        │
                ┌───────────────────────────┬───────────┴───────────────┐
                │ runs                      │ runs                      │ enqueues
                ▼                           ▼                           ▼
 ╭╌ < Funes::Projection ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╮
 ╎ ┌────────────────────────┐  ┌────────────────────────┐   ┌───────────────────────┐  ╎
 ╎ │      Consistency       │  │    n Transactional     │┐  │        n Async        │┐ ╎
 ╎ │       Projection       │  │      Projections       ││  │      Projections      ││ ╎
 ╎ └────────────────────────┘  └────────────────────────┘│  └───────────────────────┘│ ╎
 ╎                              └────────────────────────┘   └───────────────────────┘ ╎
 ╰╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌│╌╌╌╌╌╌╌╌╌╌╌╌╌╌╯
                                       perform now                perform later
                                            │                           │
                                            └─────────────┬─────────────┘
                                                          ▼
                                           ┌─────────────────────────────┐
                                           │ Funes::PersistProjectionJob │
                                           └─────────────────────────────┘
                                            < ActiveJob::Base
```

- **Events** — immutable `ActiveModel` objects that record what happened, with built-in validation and no schema migrations
- **Projections** — transform an event stream into a materialized state, either in-memory (`ActiveModel`) or persisted (usually an `ActiveRecord`)
- **Event Streams** — orchestrate writes, run double validation, and control when projections update (synchronously or through `ActiveJob`)

For a full walkthrough of each concept, see the [Concepts section](https://docs.funes.org/concepts/) of the guides.

## The DSL

The declarative DSL keeps your attention on what matters: the *interpretation of events*, not the plumbing around them.

A projection reads like a description of your domain logic:

```ruby
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, event, _at|
    state.assign_attributes(outstanding_balance: event.amount)
    state
  end

  interpretation_for Debt::PaymentReceived do |state, event, at|
    state.outstanding_balance -= event.principal_amount
    state.last_payment_at = at
    state
  end
end
```

You write no event-store wiring, no manual replay loop, and no serializer configuration. The same DSL scales from one in-memory validation to a fully persisted projection.

The chart below shows the mechanics: a projection folds the events through your interpretations, then unfolds the result into the materialization model.

```text
 ┌╌ left fold / reduce ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
 ╎                                                                 ╎      unfolding into
 ╎ ┌──────────┐   pattern matching   ┌─────────────────┐           ╎    ┌─────────────────┐
 ╎ │  Events  │ ───────────────────▶ │ Interpretations │ ──────────╎──▶ │ Materialization │
 ╎ └──────────┘                      └─────────────────┘           ╎    │      model      │
 ╎  filtered by                       defined as blocks/lambdas    ╎    └─────────────────┘
 ╎  EventStream                       in the projection definition ╎     < ActiveModel::Model (virtual)
 ╎                                                                 ╎     < ActiveRecord::Base (persistent)
 └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘
```

## Optimistic concurrency control

Funes uses optimistic concurrency control. A database constraint keeps every version number unique inside its event stream. If two processes append at the same time, both events get the same version number. The database accepts one and rejects the other, and the rejected process gets a validation error. Funes needs no locks and blocks nothing.

## Three-tier consistency model

Funes gives you fine-grained control over when and how projections run:

| Tier                      | When it runs                               | Use case                                            |
|:--------------------------|:-------------------------------------------|:----------------------------------------------------|
| Consistency projections   | Before Funes persists the event            | Validate business rules against the new state       |
| Transactional projections | Same DB transaction as the event insertion | Critical projections that need strong consistency   |
| Async projections         | Background job (ActiveJob)                 | Reports, analytics, and eventually consistent projections |

### Consistency projections

* **Guard your invariants:** consistency projections run _before_ Funes saves the event to the log. If the new state is invalid, Funes rejects the event and never persists it.
* **Validate the business logic:** prevent "impossible" states here. Two examples: you ship more inventory than you have, or you overdraw a bank deposit.

### Transactional projections

* **Atomic updates:** transactional projections update the persisted materialization in the same database transaction as the event insertion.
* **Validation before persistence:** Funes runs validations on the materialization model before its persistence. If the model is invalid, Funes raises an error and the transaction rolls back. Funes does not persist the event.
* **Fail loud on errors:** a projection can fail with a database error, such as a constraint violation, or with a validation error. The transaction then rolls back, and `persisted?` returns `false` for the event. The exceptions (`ActiveRecord::StatementInvalid` or `ActiveRecord::RecordInvalid`, for instance) propagate. This behavior makes bugs visible and leaves the event in a consistent state for your rescue logic.

### Async projections

* **Background jobs:** Funes offloads async projections to `ActiveJob`. Heavy computations then stay off the write path.
* **Native integration:** async projections work with the standard Rails job backends, such as `Sidekiq` and `Solid Queue`. You can set the standard `ActiveJob` configs, such as `queue`, `wait`, or `wait_until`.
* **Temporal control (`temporal_context`):** every interpretation block receives a timestamp as its temporal parameter. An async projection runs later, in a background job, so that timestamp needs a source. The `temporal_context` option chooses the moment that Funes passes to the blocks:
  * `:last_event_time` (the default): uses the **transaction time** (`created_at`) of the last event. Funes records that time in the database. It is not the time when the business event occurred (`occurred_at`).
  * `:job_time`: uses the current time at the moment the job runs.
  * `Proc`/`Lambda`: runs your own temporal logic. For example, round the time down to the `beginning_of_day`.

  Do not confuse `temporal_context` with the `at:` argument of `EventStream#append`. The `at:` argument sets the `occurred_at` of the event (business time), and its value does not reach async projections.

## Documentation

You can read the guides and the full API documentation at [docs.funes.org](https://docs.funes.org).

For a hands-on example, see the [Funes Workshop](https://github.com/viniciusalmeida/funes_workshop). The workshop is a small Rails app that models a debt lifecycle: loan issuance, daily interest accrual, and payments. It shows how to use Events, Event Streams, and Projections in a realistic financial domain.

## Performance

Precise benchmarks are hard to pin down. Workloads vary, and absolute numbers depend on the hardware, the configuration, and the shape of the data. Treat the figures we publish as directional, not definitive.

Our measurements show that the complexity of event stream operations stays **sub-linear, comfortably within `O(n)`**, as the log grows. This property matters for event streams with a long life.

You can browse the latest measurements and join the conversation in the [Performance Measurements](https://github.com/funes-org/funes/discussions/categories/performance-measurements) discussions.

## Compatibility

Funes supports these runtimes:

- **Ruby** 3.1 or newer
- **Rails** 7.2 or newer

If you use Rails 8.0 or newer, you also need Ruby 3.2 or newer. This limit comes from Rails 8, not from Funes.

## License

The gem is open source software under the terms of the [MIT License](https://opensource.org/licenses/MIT).
