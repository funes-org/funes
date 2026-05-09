---
title: Virtual
layout: default
parent: Setting up materialization models
grand_parent: Recipes
nav_order: 1
---

# Virtual materialization models
{: .no_toc }

After reading this guide, you will know how to build an in-memory materialization model — an `ActiveModel` that lives only for the duration of a query and is recomputed from events on demand.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

A virtual materialization model is computed on the fly. Nothing is written anywhere — every call to `projected_with` rebuilds the state from the underlying events. That makes virtual projections a natural fit for consistency checks (validating an event's effect on state before it lands) and for ad-hoc queries where you don't need a queryable read table.

## Defining the model

Virtual models are plain `ActiveModel` classes. Declare attributes and validations the same way you would on any Rails model:

```ruby
# app/models/outstanding_balance.rb
class OutstandingBalance
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :outstanding_balance, :decimal
  attribute :last_payment_at, :datetime

  validates :outstanding_balance, numericality: { greater_than_or_equal_to: 0 }
end
```

No table, no primary key, no migration. The class only needs to expose `assign_attributes`, `attributes`, `valid?`, and `errors` — all standard `ActiveModel::Model` machinery.

## Wiring it to a projection

Point a projection at the model with `materialization_model`:

```ruby
# app/projections/virtual_outstanding_balance_projection.rb
class VirtualOutstandingBalanceProjection < Funes::Projection
  materialization_model OutstandingBalance

  interpretation_for Debt::Issued do |state, event, _at|
    state.outstanding_balance = event.amount
    state
  end

  interpretation_for Debt::PaymentReceived do |state, event, at|
    state.outstanding_balance -= event.principal_amount
    state.last_payment_at = at
    state
  end
end
```

Because nothing is persisted, every call to `DebtEventStream.for(idx).projected_with(VirtualOutstandingBalanceProjection)` replays the events from scratch and returns a fresh `OutstandingBalance` instance.

## When to reach for it

- **Consistency checks** — pair a virtual projection with `consistency_projection` on an event stream so an invalid resulting state rejects the event before it is persisted. The validation rules on the model carry the invariants.
- **One-off queries** — when the access pattern doesn't justify a read table, a virtual projection is faster to set up and has zero schema cost.
- **Prototyping** — try out an interpretation shape without committing to a migration.

When the access pattern does justify a stored representation, switch to a [Persistent](/recipes/materialization-models/persistent/) materialization model — backed by the default database table or a custom destination.
