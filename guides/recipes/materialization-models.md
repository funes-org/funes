---
title: Setting up projections
layout: default
parent: Recipes
nav_order: 5
has_children: true
---

# Setting up projections

Recipes for the two flavors of projection — virtual and persistent — distinguished by *where* the projected state lives. The [Projection](/concepts/projection/) concept introduces the choice; the recipes here show how to set each one up.

- [Virtual](/recipes/materialization-models/virtual/) — projection that materializes state in memory only, recomputed on demand from the events
- [Persistent](/recipes/materialization-models/persistent/) — projection that materializes state to a durable store: an `ActiveRecord` row in a Funes-shaped table by default, or any custom destination (S3, Redis, search index, external API)
