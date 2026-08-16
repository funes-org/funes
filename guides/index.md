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

Funes gives Rails developers a frictionless way to build systems where history is as important as the present. It follows the one-person framework philosophy and honors the Rails doctrine: it applies deep **conceptual compression** to what is usually a complex architectural pattern.

The core of Funes is a declarative DSL that favors the **interpretation of events** over the plumbing. You do not wire up event stores, replay loops, or serializers. You describe how each event affects state, and Funes handles persistence, ordering, concurrency, and materialization for you:

```ruby
interpretation_for Debt::PaymentReceived do |state, event, at|
  state.outstanding_balance -= event.principal_amount
  state.last_payment_at = at
  state # returns the new state version
end
```

Funes distills the mechanics of event sourcing into three core concepts: **Events**, **Event Streams**, and **Projections**.

Traditional event sourcing tools require a shift in how you build. Funes does not: it supports **progressive adoption** and coexists with your existing Active Record models and standard controllers. You can use Funes for a single mission-critical feature and keep the rest of your app in plain Rails.

### Why event sourcing?

In a typical Rails app, data has no past — only a present. You call `update!` on a model, and the previous value is gone. Event sourcing takes a different approach: store *what happened* as immutable events, then replay those events to derive the current state.

This approach gives you:

- **A complete audit trail** — Funes records every state change, forever
- **Historic interpretation** — ask "what was the entity state on December 1st?". Bi-temporal control separates record time (when the system learned a fact) from actual time (when the event really happened)
- **Multiple interpretations** — you can interpret the same events in different ways for different use cases
- **Safer refactoring** — you can rebuild any state from the event log

Event sourcing is the right choice for any application where "what was true then?" matters as much as "what is true now?"
