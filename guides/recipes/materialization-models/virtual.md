---
title: Virtual
layout: default
parent: Setting up projections
grand_parent: Recipes
nav_order: 1
---

# Virtual projections
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Funes computes a virtual materialization model on demand, and writes nothing anywhere. That makes virtual projections a natural fit for consistency checks, where you validate an event's effect on state before it lands. They also suit ad-hoc queries where you don't need a queryable read table.

## Defining the projection's materialization model

Materialization models on virtual projections are plain `ActiveModel` classes. `ActiveModel` is a well-established Rails convention with a stable, predictable API, and Funes expects nothing beyond it. Declare attributes and validations exactly as the framework already [documents](https://guides.rubyonrails.org/active_model_basics.html):

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

No table, no primary key, no migration. To replay events, the virtual projection only needs to read and write attributes (`attributes`, `assign_attributes`) and check whether the resulting state is valid (`valid?`, `errors`). `ActiveModel::Model` and `ActiveModel::Attributes` provide every one of these.

The projection's derivative state will be an instance of this model. And again, without any side effect.

## Wiring materialization model to the projection

Tell the projection which model to materialize with `materialization_model`:

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

Because Funes persists nothing, every replay walks the events from scratch and returns a fresh `OutstandingBalance` instance.

## When to reach for it

- **Consistency checks** — pair a virtual projection with `consistency_projection` on an event stream, so an invalid resulting state rejects the event before Funes persists it. The validation rules on the model carry the invariants.
- **One-off queries** — when the access pattern doesn't justify a read table, a virtual projection is faster to set up and has zero schema cost.
- **Prototyping** — try out an interpretation shape without committing to a migration.

{: .note }
The lack of side effects is exactly what makes a virtual projection perfect as the stream's `consistency_projection`. Funes projects the resulting state through it and then calls `.valid?` on that state. That single check is the gate that decides whether the new event's append goes through.

When the access pattern does justify a stored representation, switch to a [Persistent](/recipes/materialization-models/persistent/) materialization model. It can use the default database table or a custom destination.
