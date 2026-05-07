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

An **Event** is an immutable record of something that happened. Unlike a traditional model, an event is not current state — it is a fact from history.

> **Note:** Events are facts. Once recorded, they are written in stone — Funes never updates or deletes them. If reality turns out to be different from what was recorded, you correct the record by appending a new event, not by editing the old one.

> **Note:** Choose event class names with care up front. Funes stores the literal class name in the `event_entries` table for every event ever appended, so renaming one is technically possible but never trivial — it means a data migration over every persisted event of that type, coordinated with the code rename. Treat the name as part of the fact.

## Facts, not state

Think about how a typical Rails model works: a `User` record represents who they are *now*. When their email changes, you overwrite the old value and it's gone.

An event works differently. A `User::EmailChanged` event records *what happened* — the old email, the new email, and when the change occurred. The fact is stored permanently and can never be updated.

This distinction is the foundation of event sourcing. Your system's history becomes the source of truth, and current state is derived from it.

## Defining an event

Events inherit from `Funes::Event` and behave like `ActiveModel` objects. You define their attributes and validations just as you would on any Rails model:

```ruby
# app/events/debt/issued.rb
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
