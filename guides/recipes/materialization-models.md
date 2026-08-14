---
title: Set up projections
layout: default
parent: Recipes
nav_order: 1
has_children: true
---

# Set up projections

These recipes cover the two flavors of projection — virtual and persistent. The flavors differ in *where* the projected state lives. The [Projection](/concepts/projection/) concept introduces the choice; the recipes here show how to set each one up.

- [Virtual](/recipes/materialization-models/virtual/) — a projection that materializes state in memory only; Funes recomputes it on demand from the events — ideal for consistency checks
- [Persistent](/recipes/materialization-models/persistent/) — a projection that materializes state to a durable store: an `ActiveRecord` row in a Funes-shaped table by default, or any custom destination (S3, Redis, search index, external API)
