---
title: Setting up materialization models
layout: default
parent: Recipes
nav_order: 5
has_children: true
---

# Setting up materialization models

Recipes for the materialization models that back a projection — picking the right one is the call you make about *where* the projection's state lives. The [Projection](/concepts/projection/) concept introduces the choice; the recipes here show how to set each one up.

- [Virtual](/recipes/materialization-models/virtual/) — in-memory `ActiveModel`, recomputed on demand from the events
- [Persistent](/recipes/materialization-models/persistent/) — written somewhere durable: an `ActiveRecord` row in a Funes-shaped table by default, or any custom destination (S3, Redis, search index, external API)
