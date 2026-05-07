---
title: "Event errors: own_errors, state_errors, errors"
layout: default
parent: Recipes
nav_order: 4
---

# Event errors: own_errors, state_errors, errors
{: .no_toc }

After reading this guide, you will know the three error collections every Funes event carries — `own_errors`, `state_errors`, and `errors` — and when to read each one.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

When you append an event, two independent things can go wrong: the event itself can be invalid (`amount` is negative), or the event can be valid but lead to an invalid state once a consistency projection replays it (the payment would overdraw the account). Funes keeps these two failure modes apart so your form can show the right message in the right place.

Every event exposes three error collections. They all return `ActiveModel::Errors`, so anything you'd do with a Rails model's `errors` works here too.

## `own_errors` — unit-validation failures

`own_errors` carries the errors produced by the event class's own `ActiveModel` validators — the ones you wrote on the event itself. Read it when you want to surface only what the event got wrong before any projection saw it:

```ruby
event = Order::Placed.new(total: -10)
event.valid?
event.own_errors.full_messages
# => ["Total must be greater than 0"]
```

It also includes any errors added inside the event's interpretation blocks via `event.errors.add(...)`, which a consistency projection uses to reject the event explicitly.

## `state_errors` — consistency-projection failures

`state_errors` carries the errors from the consistency projection — the validations that ran on the resulting state, not on the event:

```ruby
event = stream.append(Inventory::ItemShipped.new(quantity: 9999))
event.state_errors.full_messages
# => ["Quantity on hand must be >= 0"]
```

If the event itself is fine but its effect violates a business rule, the message lands here.

## `errors` — both collections, merged

`errors` returns the union of `own_errors` and `state_errors`. State errors are wrapped with a localized prefix (`"Led to invalid state: …"`) so you can tell at a glance which side of the validation rejected them:

```ruby
event = stream.append(Order::Placed.new(total: -10))
event.errors.full_messages
# => ["Total must be greater than 0",
#     "Led to invalid state: Quantity on hand must be >= 0"]
```

This is the collection `form_with` reads when it renders an error summary, and the one to call from a controller when you just want every reason the append failed.

## Choosing the right one

A quick rule of thumb:

- Re-rendering a form? Use `errors` — `form_with` and `errors.full_messages` already do the right thing.
- Highlighting a specific field on the form? Use `own_errors` — you only want the event's own field-level failures, not the cross-cutting state errors.
- Logging or routing a specific failure mode (alerting on overdrafts, for example)? Use `state_errors` — they tell you which projection rejected the event.

> **Note:** The prefix on `state_errors` is localized via `funes.events.led_to_invalid_state_prefix`. See the [Rails I18n for events](rails-i18n-for-events) recipe to translate it.
