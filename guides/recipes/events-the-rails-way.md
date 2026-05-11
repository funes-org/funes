---
title: Events as first-class Rails citizens
layout: default
parent: Recipes
nav_order: 2
has_children: true
---

# Events as first-class Rails citizens
{: .no_toc }

Events in Funes aren't a separate idea bolted onto Rails — they're first-class citizens of the same stack you already use, at the same level as an `ActiveRecord` model. You wire them into the UI, the controller, the I18n files, and the request cycle the exact same way: `ActiveModel` validations, `form_with`, strong parameters, the `persisted?`/`errors` cycle, the same `activemodel.attributes` and `activemodel.errors` translation keys. Recording an event is one new method (`append`) layered on top of patterns you've used for years.

(If you're new to the event class itself, see the [Event](/concepts/event/) concept for what an event is and how it differs from an `ActiveRecord` model.)

The pages below walk through the everyday Rails tasks where this parity shows up:

- [Rendering events in a form](/recipes/events-the-rails-way/forms/) — pass an event to `form_with` and let the standard helpers handle labels, fields, and errors.
- [Appending events from a controller](/recipes/events-the-rails-way/controllers/) — build the event from strong params, call `.append`, and read `persisted?` just like `save`.
- [Rendering 404s from empty streams](/recipes/events-the-rails-way/show-actions/) — `projected_with` returns the materialization model on a hit and raises `ActiveRecord::RecordNotFound` on a miss, so Rails 404s automatically — no rescue code needed.
- [Translating attributes and messages](/recipes/events-the-rails-way/translations/) — the same `activemodel.attributes` and `activemodel.errors` I18n keys you already use, plus the two Funes-specific keys for rejected appends.

## Going further

- Coordinate appends with sibling writes via the [Atomic writes](/recipes/atomic-writes/) recipe.
- Attach acting-user and request context to every event with the [Attaching meta information to events](/recipes/attaching-meta-information/) recipe.
