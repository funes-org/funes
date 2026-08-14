---
title: Reference Active Record models
layout: default
parent: Recipes
nav_order: 9
---

# Reference Active Record models
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

Most facts point at something in your existing Rails app: you issue a debt *to a customer*, a payment lands *in an account*. But Funes serializes an event as plain JSON in the `props` column, so the event cannot hold an Active Record object. `refers_to` gives you the association-like API you'd expect, while it stores only what belongs in an immutable fact — the referenced model's id.

This recipe assumes you're comfortable with [events](/concepts/event/) and [projections](/concepts/projection/).

## Declare a reference on an event

Call `refers_to` in the event definition, alongside your attributes:

```ruby
# app/models/events/debt/issued.rb
module Debt
  class Issued < Funes::Event
    refers_to :customer

    attribute :amount, :decimal
    attribute :at, :datetime

    validates_presence_of :at
    validates :amount, numericality: { greater_than: 0 }
  end
end
```

That single line defines three things: a `customer_id` attribute, a `customer=` writer that accepts the model, and a `customer` reader that loads it back.

```ruby
customer = Customer.find(42)
event = Debt::Issued.new(customer: customer, amount: 1_000, at: Time.current)

event.customer_id  # => 42
event.customer     # => #<Customer id: 42, name: "Ada">
event.attributes   # => { "amount" => 1000, "at" => ..., "customer_id" => 42 }
```

Notice what `attributes` contains: `customer_id`, never `customer`. The id is everything that Funes writes to the log.

## Read the reference in an interpretation

Because the reader is just a method on the event, interpretation blocks use it directly:

```ruby
# app/projections/debt_summary_projection.rb
interpretation_for Debt::Issued do |state, event, at|
  state.customer_name = event.customer.name
  state.outstanding_balance = event.amount
  state
end
```

The reader fetches the model lazily on that first call and memoizes it afterwards, so a stream replay doesn't re-query for every event that shares a reference.

{: .note }
The reader returns the referenced model's **current** state — it's a live lookup, not a snapshot of how the model looked when the event happened. If the fact itself needs the old value (the customer's name *at the time*), copy that value into an attribute on the event instead. And if the model no longer exists, the reader returns `nil` rather than raise an error.

## Options

`refers_to` accepts the same three options you'd expect from `belongs_to`:

```ruby
module Loan
  class Granted < Funes::Event
    refers_to :borrower, class_name: "User", required: true
    refers_to :account, foreign_key: :account_uuid
  end
end
```

| Option | What it does | Default |
|:-------|:-------------|:--------|
| `class_name` | Name of the referenced class, as a **string** — the class object itself raises `ArgumentError`. It must be fully qualified for namespaced models (`"Billing::Customer"`). Funes resolves it lazily, so autoloading stays happy. | The camelized reference name |
| `foreign_key` | The attribute that stores the id | `"#{name}_id"` |
| `required` | Adds a presence validation on the foreign key, so an event without the reference is invalid and never reaches the log | `false` |

Declare as many references as you need, including two that point at the same class:

```ruby
module Trade
  class Settled < Funes::Event
    refers_to :buyer, class_name: "Customer"
    refers_to :seller, class_name: "Customer"
  end
end
```

## References on materialization models

A projection's state is an instance of its materialization model, so it's often the natural place to keep the reference too. Include `Funes::Associations` and declare `refers_to` the same way:

```ruby
# app/models/debt_summary.rb
class DebtSummary
  include ActiveModel::Model
  include ActiveModel::Attributes
  include Funes::Associations

  refers_to :customer

  attribute :outstanding_balance, :decimal
end
```

Now the reference reads and writes identically on both sides of the block — you can hand it straight from the event to the state:

```ruby
interpretation_for Debt::Issued do |state, event, _at|
  state.customer = event.customer
  state.outstanding_balance = event.amount
  state
end
```

```ruby
summary = stream.projected_with(DebtSummaryProjection)
summary.customer # => #<Customer id: 42, name: "Ada">
```

Only the id travels in `attributes`, so the reference survives the rebuild that `materialize!` performs. This works for [virtual](/recipes/materialization-models/virtual/) materialization models and for those you persist through `persist_materialization_model_with`.

## A note on ActiveRecord materialization models

{: .warning }
For an **ActiveRecord-backed** materialization model, declare a regular `belongs_to` association instead. That's the idiomatic tool there, and it brings preloading and `inverse_of` with it.

`refers_to` can work on such a model, but only when the foreign key already exists as a column — and even then `belongs_to` remains the better choice. Without that column the failure arrives late and points at the wrong thing: your interpretation blocks read and write the reference correctly, Funes fills the foreign key, and then `materialize!` feeds `attributes` into an upsert and raises

```
ActiveModel::UnknownAttributeError: unknown attribute 'customer_id' for DebtSummary.
```

The error names the attribute but mentions neither the missing column nor the `refers_to` call that created it, so it surfaces far from its cause. Save yourself the hunt and use `belongs_to`.
