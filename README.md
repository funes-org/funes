# Funes

An event sourcing meta-framework designed to provide a frictionless experience for RoR developers to build and operate systems where history is as important as the present. Built with the one-person framework philosophy in mind, it honors the Rails doctrine by providing deep **conceptual compression** over what is usually a complex architectural pattern.

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

## Optimistic concurrency control

Funes uses optimistic concurrency control. Each event in a stream gets an incrementing version number with a unique constraint on (idx, version).

If two processes try to append to the same stream simultaneously, one succeeds and the other gets a validation error — no locks, no blocking.

## Documentation

Guides and full API documentation are available at [docs.funes.org](https://docs.funes.org).

## Compatibility

- **Ruby:** 3.1, 3.2, 3.3, 3.4
- **Rails:** 7.1, 7.2, 8.0, 8.1

Rails 8.0+ requires Ruby 3.2 or higher.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
