---
title: Per-change Projections
layout: default
parent: Core Concepts
nav_order: 4
---

# Per-change Projections
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

After reading this guide, you will know:

- What a **per-change projection** is and when to reach for one.
- How to configure a projection so each change to its state is persisted as its own row.
- How the `final_state` hook shows up as a dedicated `"final"` row.
- Which guarantees Funes makes about the write (atomicity, idempotence), and which it does not.

## What is a per-change projection?

A regular [persistent projection](../projections#persistent-projections) keeps a single row per `idx` — the final state of the fold. That is the right default when you only care about "what does this entity look like right now?"

A **per-change projection** keeps one row for each version of the state instead. After the fold, the materialization table holds a row per event position that had an interpretation, plus an optional `"final"` row when the projection declares a `final_state` hook. It is the same fold, the same interpretations, the same `at` temporal reference — only the persistence shape changes.

Reach for this when you need to answer questions like "what did this entity look like at event N?" without re-running the fold every time.

## Enabling per-change persistence

Opt in on the projection with `persists_per_change`:

```ruby
# app/projections/balance_history_projection.rb
class BalanceHistoryProjection < Funes::Projection
  materialization_model BalanceHistory
  persists_per_change

  interpretation_for Deposit::Created do |state, event, _at|
    state.assign_attributes(balance: event.value)
    state
  end

  interpretation_for Deposit::Withdrawn do |state, event, _at|
    state.assign_attributes(balance: state.balance - event.amount)
    state
  end
end
```

Regular persistent projections in your app are unaffected — `persists_per_change` flips behavior only for the projection that declares it.

## The materialization table

Per-change tables have a composite primary key on `(idx, version)` instead of the single `idx`. Funes ships a dedicated generator that writes the right migration:

```bash
$ bin/rails generate funes:per_change_materialization_table BalanceHistory balance:decimal
$ bin/rails db:migrate
```

This produces a migration that creates the table with `id: false`, a composite primary key on `(idx, version)`, and a unique index on the same pair.

The model mirrors the composite key:

```ruby
# app/models/balance_history.rb
class BalanceHistory < ApplicationRecord
  self.primary_key = [ :idx, :version ]
end
```

> **Warning:** If you declare `persists_per_change` but the underlying table is missing the `version` column, Funes raises `Funes::InvalidPerChangeMaterializationTable` the first time it tries to persist. The message points you at the generator.

## What gets written

Given three events that all have interpretations, Funes writes three rows:

| idx         | version | balance |
|-------------|---------|---------|
| `account-1` | `"1"`   | 100     |
| `account-1` | `"2"`   | 70      |
| `account-1` | `"3"`   | 50      |

A few details worth knowing:

- The `version` column is a **string**. Event-position versions are 1-indexed stringified integers (`"1"`, `"2"`, …); the sentinel `"final"` is also a string.
- `version` is the position of the event in the collection Funes receives, not an auto-incrementing counter. Events without a matching `interpretation_for` produce no row, so versions can skip (`"1"`, `"3"`, `"5"`).
- The row for `version = "1"` is the snapshot *after* the first interpreted event has run. You never see the pre-fold initial state on its own row.

## The `"final"` row

When your projection declares a [`final_state`](../projections#lifecycle-hooks) hook, Funes writes one additional row with `version = "final"`:

```ruby
class BalanceHistoryProjection < Funes::Projection
  materialization_model BalanceHistory
  persists_per_change

  interpretation_for Deposit::Created   { |state, e, _at| state.assign_attributes(balance: e.value); state }
  interpretation_for Deposit::Withdrawn { |state, e, _at| state.assign_attributes(balance: state.balance - e.amount); state }

  final_state do |state, at|
    # derive or annotate a settled final state, possibly using the query's `at`
    state
  end
end
```

The `"final"` row is a first-class version, not an index or a shortcut. Its contents come from whatever your `final_state` hook returns — which may differ from the highest event-position row if, for example, your hook uses the query's `at` to compute a settled state that no single event produced.

If you do not declare `final_state`, no `"final"` row exists, and the highest event-position row represents the most recent state.

## Re-projection guarantees

Each time a per-change projection runs for an `idx`, Funes computes the full set of versions in memory and, inside a single database transaction, does the write as a unit:

1. Delete every existing row for that `idx`.
2. Insert the freshly computed rows.

This gives you two properties:

- **Atomic.** Readers never see the table mid-rebuild. If anything in the run fails — a validation, a constraint, a connection hiccup — the prior rows remain intact.
- **Consistent under changing interpretations.** If your projection stops interpreting an event type between runs, the next run's table state reflects the current code, not a patchwork of what past versions of the projection used to produce.

## What this feature does not give you

These rows are **not immutable**. Re-projection rewrites them whenever the projection's logic changes. If your consumer needs immutability — an accounting ledger, a regulatory record — the immutability has to live at that layer, not here.

Funes does not version your projector code, either. Two runs with different interpretation logic will produce two different tables for the same events, and the later one wins.

## Related guides

- [Projections](../projections) — the default single-row persistence model.
- [Temporal Queries](../temporal-queries) — how `at` flows through the fold and into `final_state`.
