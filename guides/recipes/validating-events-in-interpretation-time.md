---
title: Validate events in interpretation time
layout: default
parent: Recipes
nav_order: 3
---

# Validate events in interpretation time
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Funes replays events through a projection in a fixed two-step cycle: **interpret first, validate after**. Each `interpretation_for` block runs to update the materialization state. Funes verifies the result only after the replay is done: it calls `materialization.valid?` on the resulting state.

That cycle handles declarative rules cleanly. The validation step catches an event with a missing required attribute, or a materialization that violates one of its `validates` rules, without any imperative code on your side. What it can't express is a rule that depends on the *combination* of event and state: you can detect a payment that exceeds the outstanding balance, for instance, only when you see both at once. And that view exists nowhere except inside the interpretation block.

This feature lets you represent errors at **interpretation time**: push an error onto the event with `event.errors.add(...)` while the interpretation block still runs. You don't wait for the static validation step at the end. The error rides along with the event into the same `event.valid?` check that runs after the replay completes — but you author it against the state-aware view that exists only mid-block.

## Add an error from an interpretation block

Inside any `interpretation_for` block, the event is mutable: call `event.errors.add(...)` to attach a validation error scoped to a specific attribute or to `:base`.

```ruby
class OutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::PaymentReceived do |state, event, _at|
    if event.principal_amount > state.outstanding_balance
      event.errors.add(:principal_amount, "exceeds outstanding balance")
    end
    state.outstanding_balance -= event.principal_amount
    state
  end
end
```

In this sample, the interpretation block sees both sides — `event.principal_amount` and `state.outstanding_balance` — a view that a model-level `validates` on `OutstandingBalance` does not have.

{: .important }
This pattern earns its place in **consistency projections**. An invalid event — an overpayment, in our example — must never reach the log, and the consistency projection is the only tier that runs *before* persistence. During an append, this error rolls back the database transaction and lands in the event's error collections.

## Read the errors after a rejected append

Interpretation-time errors land in `own_errors`, alongside any failures from the event class's own `validates` rules — they all describe why Funes rejected the event itself.

```ruby
event = stream.append(Debt::PaymentReceived.new(principal_amount: 9999))
event.persisted?               # => false
event.own_errors.full_messages # => ["Principal amount exceeds outstanding balance"]
```

For the full breakdown of `own_errors`, `state_errors`, and the merged `errors` collection — and the proper situation to read each one of them — see [Read the right error collection](/recipes/error-collections/).
