---
title: Recipes
layout: default
nav_order: 4
has_children: true
---

# Recipes

The recipes in this section are task-focused guides for the things you actually do with Funes. Each recipe assumes that you've met the [Concepts](/concepts/) and shows you how to put them to work in a real Rails app: append events from controllers, translate messages, coordinate with sibling writes, interpret events with a historic perspective, and ship projections to the destination that fits.

- [Set up projections](/recipes/materialization-models/) — virtual or persistent (default-database or custom-destination) projections
- [Events as first-class Rails citizens](/recipes/events-the-rails-way/) — forms, controllers, and I18n all work as you'd expect
- [Validate events in interpretation time](/recipes/validating-events-in-interpretation-time/) — add errors from inside an interpretation block, with both the event and the state in view
- [Read the right error collection](/recipes/error-collections/) — pick between `own_errors`, `state_errors`, and the merged `errors` for what you need to show
- [Atomic writes](/recipes/atomic-writes/) — coordinate `append!` with sibling writes inside a transaction you control
- [Attach meta information to events](/recipes/attaching-meta-information/) — record the user and request context behind every event
- [Build bi-temporal event streams](/recipes/bi-temporal-event-streams/) — interpret with `as_of` and `at` for full historical reconstruction
- [Test projections](/recipes/testing-projections/) — exercise interpretations in isolation with `ProjectionTestHelper`
- [Reference Active Record models](/recipes/referencing-active-record-models/) — point events and materialization models at the rest of your Rails app with `refers_to`
