---
title: Home
layout: home
nav_order: 1
---

# Funes
{: .fs-9 }

A frictionless event sourcing experience for Rails developers.
{: .fs-6 .fw-300 }

[Get started](/getting-started/){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/funes-org/funes){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## About

Funes gives RoR developers a frictionless experience building systems where history matters as much as the present. We built it with the one-person framework philosophy in mind. It honors the Rails doctrine by providing deep **conceptual compression** over what is usually a complex architectural pattern.

At its core is a declarative DSL that favors the **interpretation of events** over all the plumbing. Instead of wiring up event stores, replay loops, and serializers, you describe how each event affects state. Funes handles persistence, ordering, concurrency, and materialization for you:

```ruby
interpretation_for Debt::PaymentReceived do |state, event, _at|
  state.outstanding_balance -= event.principal_amount
  state.last_payment_at = event.at
  state
end
```

Funes distills the mechanics of event sourcing into just three core concepts: **Events**, **Event Streams**, and **Projections**. It handles the underlying complexity of persistence and state reconstruction for you.

Traditional event sourcing frameworks require a total shift in how you build. Funes instead supports **progressive adoption**. It coexists seamlessly with your existing ActiveRecord models and standard controllers. You can use Funes for a single mission-critical feature while keeping the rest of your app in plain Rails.

### Why event sourcing?

In a typical Rails app, data has no past — only a present. You `update!` a record and the previous value is gone. Event sourcing takes a different approach: store *what happened* as immutable events, then derive the current state by replaying them.

This gives you:

- **Complete audit trail** — Funes records every state change, forever
- **Temporal queries** — what was the entity state on December 1st? You get full bi-temporal control over record time (when the system learned a fact) and actual time (when it really happened)
- **Multiple interpretations** — the same events, different ways to interpret state for different use cases
- **Safer refactoring** — rebuild any state from the event log

It's the right choice for any application where "what was true then?" matters as much as "what is true now?"
