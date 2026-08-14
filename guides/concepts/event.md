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

An **Event** is an immutable fact: something that happened. Unlike a traditional model, an event is not current state — it is a fact from history. After Funes records an event, the fact is written in stone: Funes never updates or deletes it.

How to handle events that no longer reflect reality is a well-studied topic; Greg Young's [*Versioning in an Event Sourced System*](https://leanpub.com/esversioning#table-of-contents) is a thorough reference.

{: .warning }
Choose event class names with care up front. Funes stores the literal class name in the `event_entries` table for every event that you append. A rename is possible but never trivial: it requires a data migration over every persisted event of that type, together with the code rename. Treat the name as part of the fact.

## Facts, not state

Think about how a typical Rails model works: a `Debt` model carries the outstanding balance *now*. When a payment comes in, you decrement that balance — and the payment itself, in all its detail, is gone.

An event works differently. A `Debt::PaymentReceived` event records *what happened* — the principal amount, the interest amount, and when the payment occurred. Funes stores the fact permanently and never updates it.

This distinction is the foundation of event sourcing. Your system's history becomes the source of truth, and Funes derives the current state from it.

## Define an event

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

## Reference other models

Facts rarely happen in a vacuum — you issue a debt *to a customer*, you receive a payment *from an account*. Because Funes serializes an event as plain JSON, the event cannot carry another model inside it. The `refers_to` declaration bridges that gap:

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

You assign and read the model itself, and Funes stores only its id in the payload:

```ruby
event = Debt::Issued.new(customer: customer, amount: 1_000)
event.customer_id # => 42, the only thing that gets serialized
event.customer    # => #<Customer id: 42, name: "Ada">
```

The reader loads the model lazily, so the reference is available inside an interpretation block and does not bloat the stored fact. Read more in [Reference Active Record models](/recipes/referencing-active-record-models/).

---

Up next: [Event Stream](/concepts/event-stream/), the concept that groups events by entity, validates them, and writes them to the log.
