---
title: Home
layout: home
nav_order: 1
---

# Funes
{: .fs-9 }

A frictionless event sourcing experience for Rails developers.
{: .fs-6 .fw-300 }

[Get started](#getting-started){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/funes-org/funes){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## About

Funes is designed to give RoR developers a frictionless experience building systems where history is as important as the present. Built with the one-person framework philosophy in mind, it honors the Rails doctrine by providing deep **conceptual compression** over what is usually a complex architectural pattern.

At its core is a declarative DSL that favors the **interpretation of events** over all the plumbing. Instead of wiring up event stores, replay loops, and serializers, you describe how each event affects state — and Funes handles persistence, ordering, concurrency, and materialization for you:

```ruby
interpretation_for Debt::PaymentReceived do |state, event, _at|
  state.outstanding_balance -= event.principal_amount
  state.last_payment_at = event.at
  state
end
```

By distilling the mechanics of event sourcing into just three core concepts — **Events**, **Streams**, and **Projections** — Funes handles the underlying complexity of persistence and state reconstruction for you. It feels like the Rails you already know, giving you the power of a permanent source of truth with the same ease of use as a standard ActiveRecord model.

Unlike traditional event sourcing frameworks that require a total shift in how you build, Funes is designed for **progressive adoption**. It coexists seamlessly with your existing ActiveRecord models and standard controllers. You can use Funes for a single mission-critical feature while keeping the rest of your app in plain Rails.

### Why event sourcing?

In a typical Rails app, data has no past — only a present. You `update!` a record and the previous value is gone. Event sourcing takes a different approach: store *what happened* as immutable events, then derive the current state by replaying them.

This gives you:

- **Complete audit trail** — every state change is recorded, forever
- **Temporal queries** — "what was the entity state on December 1st?"
- **Multiple read models** — the same events, different projections for different use cases
- **Safer refactoring** — rebuild any projection from the event log

It's the right choice for any application where "what was true then?" matters as much as "what is true now?"

---

## Getting started

You'll add Funes to a Rails application and set up the database it uses to store events. Two short steps.

### Installing the gem

Add Funes to your Gemfile:

```ruby
gem "funes-rails"
```

Then install it:

```bash
$ bundle install
```

### Setting up the database

Funes stores all events in a single table called `event_entries`. Generate the migration that creates it:

```bash
$ bin/rails generate funes:install
```

This creates a migration file under `db/migrate/`. Open it and you'll see it sets up the `event_entries` table with the columns Funes needs: the event class, a stream identifier, the event attributes as JSON, a version number for concurrency control, and two timestamps — `created_at` for when the event was recorded and `occurred_at` for when it actually happened.

Now run the migration:

```bash
$ bin/rails db:migrate
```

Your database is ready. Funes will start appending events to `event_entries` as soon as you define your first event stream.

### Where to next

- The [Concepts](concepts) section explains events, streams, and projections — the three ideas Funes is built around.
- The [Recipes](recipes) section shows how to apply them: appending from controllers, querying historically, shipping projections to S3, and more.
