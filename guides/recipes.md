---
title: Recipes
layout: default
nav_order: 4
has_children: true
---

# Recipes

Task-focused guides for the things you actually do with Funes. Each recipe assumes you've met the [Concepts](/concepts/) and shows you how to put them to work in a real Rails app — appending events from controllers, translating messages, coordinating with sibling writes, querying history, and shipping projections to whatever destination fits.

- [Atomic writes](/recipes/atomic-writes/) — coordinate `append!` with sibling writes inside a transaction you control
- [Events the Rails way](/recipes/events-the-rails-way/) — define events as `ActiveModel`, render them in forms, surface errors, and translate every label
- [Attaching meta information to events](/recipes/attaching-meta-information/) — record the user and request context behind every event
- [Building bi-temporal event streams](/recipes/bi-temporal-event-streams/) — query by `as_of` and `at` for full historical reconstruction
- [Setting up projections](/recipes/materialization-models/) — virtual or persistent (default-database or custom-destination) projections
- [Testing projections](/recipes/testing-projections/) — exercise interpretations in isolation with `ProjectionTestHelper`
