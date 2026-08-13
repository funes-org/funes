---
title: Event
layout: default
parent: Concepts
nav_order: 1
---

# Event
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

An **Event** is an immutable record of something that happened. Unlike a traditional model, an event is not current state — it is a fact from history. Funes never updates or deletes an event once it lands in the log. 

How to handle events that no longer reflect reality is a well-studied topic; Greg Young's [*Versioning in an Event Sourced System*](https://leanpub.com/esversioning#table-of-contents) is a thorough reference.

{: .warning }
Choose event class names with care up front. Funes stores the literal class name in the `event_entries` table for every event you append. Renaming one is technically possible but never trivial: it means a data migration over every persisted event of that type, coordinated with the code rename. Treat the name as part of the fact.

## Facts, not state

Think about how a typical Rails model works: a `Debt` record carries the outstanding balance *now*. When a payment comes in, you decrement that balance — and the payment itself, in all its detail, is gone.

An event works differently. A `Debt::PaymentReceived` event records *what happened* — the principal amount, the interest amount, and when the payment occurred. Funes stores the fact permanently, and nothing can ever update it.

This distinction is the foundation of event sourcing. Your system's history becomes the source of truth, and current state is derived from it.

## Defining an event

Events inherit from `Funes::Event` and behave like `ActiveModel` objects. You define their attributes and validations just as you would on any Rails model:

```ruby
# app/models/events/debt/issued.rb
module Debt
  class Issued < Funes::Event
    attribute :amount, :decimal
    attribute :interest_rate, :decimal
    attribute :at, :datetime

    validates_presence_of :at
    validates :amount, numericality: { greater_than: 0 }
    validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }
  end
end
```

Because events are `ActiveModel` instances and not `ActiveRecord` models, they are **schema-independent**. Your historical facts never need a migration just because your UI requirements changed.

## Referencing other models

Facts rarely stand alone — you issue a debt *to a customer*, you receive a payment *from an account*. Since Funes serializes an event as plain JSON, it cannot carry another model inside it. Declaring `refers_to` bridges that gap:

```ruby
# app/models/events/debt/issued.rb
module Debt
  class Issued < Funes::Event
    refers_to :customer

    attribute :amount, :decimal
    attribute :at, :datetime
  end
end
```

You assign and read the record itself, while Funes stores only its id in the payload:

```ruby
event = Debt::Issued.new(customer: customer, amount: 1_000)
event.customer_id # => 42, the only thing that gets serialized
event.customer    # => #<Customer id: 42, name: "Ada">
```

The reader loads the record lazily, so the reference is there for you inside an interpretation block without bloating the stored fact. Read more in [Referencing Active Record models](/recipes/referencing-active-record-models/).

---

Up next: [Event Stream](/concepts/event-stream/), the concept that groups events by entity, validates them, and writes them to the log.
