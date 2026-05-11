---
title: Validating events during replay
layout: default
parent: Recipes
nav_order: 3
---

# Validating events during replay
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Funes replays events through a projection in a fixed two-step cycle: **interpret first, validate after**. Each `interpretation_for` block runs to update the materialization state, and only when the replay is done does Funes verify the result — calling `materialization.valid?` against the resulting state.

That cycle handles declarative rules cleanly. An event with a missing required attribute, or a materialization that violates one of its `validates` rules, gets caught at the validation step without any imperative code on your side. What it can't express is a rule that depends on the *combination* of event and state: a payment that exceeds the outstanding balance, for instance, can only be detected if you can see both at once. And that view exists nowhere except inside the interpretation block.

What this feature brings is the capacity to represent errors at **interpretation time**: programmatically push an error onto the event with `event.errors.add(...)` while the interpretation block is still running, instead of waiting for the static validation step at the end. The error rides along with the event into the same `event.valid?` check that runs after the replay completes — it just happens to have been authored against the state-aware view only available mid-block.

## Adding an error from an interpretation block

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

In this sample the errors method sees both sides — `event.principal_amount` and `state.outstanding_balance` — which a model-level `validates` on `OutstandingBalance` could not.

{: .important }
This pattern earns its place in **consistency projections**. An invalid event — an overpayment, in our example — must never reach the log, and the consistency projection is the only tier that runs *before* persistence. This error, while appending an event, rolls back the database transaction and properly manages the errors.

## Reading the errors after a rejected append

Interpretation-time errors land in `own_errors`, alongside any failures from the event class's own `validates` rules — they all describe something the event itself was rejected for.

```ruby
event = stream.append(Debt::PaymentReceived.new(principal_amount: 9999))
event.persisted?               # => false
event.own_errors.full_messages # => ["Principal amount exceeds outstanding balance"]
```

For the full breakdown of `own_errors`, `state_errors`, and the merged `errors` collection — and the proper situation to read each one of them — see [Reading the right error collection](/recipes/error-collections/).
