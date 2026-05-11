---
title: Recipes
layout: default
nav_order: 4
has_children: true
---

# Recipes

Task-focused guides for the things you actually do with Funes. Each recipe assumes you've met the [Concepts](/concepts/) and shows you how to put them to work in a real Rails app — appending events from controllers, translating messages, coordinating with sibling writes, querying history, and shipping projections to whatever destination fits.

- [Setting up projections](/recipes/materialization-models/) — virtual or persistent (default-database or custom-destination) projections
- [Events as first-class Rails citizens](/recipes/events-the-rails-way/) — forms, controllers, and I18n all work as you'd expect
- [Validating events during replay](/recipes/validating-events-during-replay/) — add errors from inside an interpretation block, with both event and state in view
- [Reading the right error collection](/recipes/error-collections/) — pick between `own_errors`, `state_errors`, and the merged `errors` depending on what you need to show
- [Atomic writes](/recipes/atomic-writes/) — coordinate `append!` with sibling writes inside a transaction you control
- [Attaching meta information to events](/recipes/attaching-meta-information/) — record the user and request context behind every event
- [Building bi-temporal event streams](/recipes/bi-temporal-event-streams/) — query by `as_of` and `at` for full historical reconstruction
- [Testing projections](/recipes/testing-projections/) — exercise interpretations in isolation with `ProjectionTestHelper`
