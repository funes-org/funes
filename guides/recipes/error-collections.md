---
title: Reading the right error collection
layout: default
parent: Recipes
nav_order: 4
---

# Reading the right error collection
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

When an append fails, two independent things can have gone wrong: the event itself can be invalid, or the event can be valid but lead to an invalid state once a consistency projection replays it. Funes keeps these two failure modes apart so your form can show the right message in the right place.

Every event exposes three error collections. They all return `ActiveModel::Errors`, so anything you'd do with a Rails model's `errors` works here too.

{: .important }
Handle these errors at event creation time. The event log is meant to record what really happened, so the developer's job is to keep bad events out of it in the first place. The three error collections below exist so you can surface the right message in the right place when an append doesn't go through, but the goal is always the same: keep the log as correct as you possibly can.

## `own_errors` — event-side failures

`own_errors` carries the errors that describe something the event itself got wrong. That covers two sources: the `validates` rules you declared on the event class, and any errors pushed during interpretation via `event.errors.add(...)`. Read it when you want to surface only the event-side failures, regardless of which path put them there:

```ruby
event = Order::Placed.new(total: -10)
event.valid?
event.own_errors.full_messages
# => ["Total must be greater than 0"]
```

See [Validating events during replay](/recipes/validating-events-during-replay/) for how a consistency projection uses the interpretation-time path to reject an event explicitly.

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

## Choosing the right one

A quick rule of thumb:

- Highlighting a specific field on the form? Use `own_errors` — you only want the event's own field-level failures, not the cross-cutting state errors.
- Highlighting how a specific event led to invalid state on its creation form? Use `state_errors` on the form's header after returning an `:unprocessable_entity`
