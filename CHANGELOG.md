# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** the entries up to 0.2.5 were written retroactively, reconstructed from
> the git history, merged pull requests, and the RubyGems release dates.

## [Unreleased]

### Changed

- `Funes::Projection` now sources its configuration during `initialize`, making
  projection instances self-contained ([#69](https://github.com/funes-org/funes/pull/69))

### Documentation

- README links to the [Funes Workshop](https://github.com/viniciusalmeida/funes_workshop)
  example application ([#68](https://github.com/funes-org/funes/pull/68))

## [0.2.5] - 2026-05-14

### Changed

- **Breaking:** renamed the projection DSL `raise_on_unknown_events` to
  `strict_mode!` ([#67](https://github.com/funes-org/funes/pull/67))

### Documentation

- Renamed the event-validation guide to "Validating events in interpretation
  time" ([#66](https://github.com/funes-org/funes/pull/66))

## [0.2.4] - 2026-05-12

### Changed

- **Breaking:** simplified the `Funes::ProjectionTestHelper` API — `final_state`
  now receives the event list through the `given:` keyword
  ([#65](https://github.com/funes-org/funes/pull/65))

### Documentation

- Restructured the guides site into "Concepts" and "Recipes" sections, and
  updated the Testing Projections recipe for the new helper API
  ([#64](https://github.com/funes-org/funes/pull/64),
  [#65](https://github.com/funes-org/funes/pull/65))

## [0.2.3] - 2026-05-07

### Added

- `persist_materialization_model_with` DSL for pluggable projection
  persistence — override how a projection persists its materialization model
  ([#61](https://github.com/funes-org/funes/pull/61))

### Documentation

- README polish: compatibility matrix, performance notes, and `append!`
  examples cleanup ([#62](https://github.com/funes-org/funes/pull/62))

## [0.2.2] - 2026-04-22

### Added

- `EventStream#append!` for host-managed transactions — append events from
  inside a transaction opened by the host application
  ([#57](https://github.com/funes-org/funes/pull/57))

### Changed

- `EventStream#projected_with` now raises `ActiveRecord::RecordNotFound` when
  the stream has no events (or every event is filtered out by the temporal
  parameters), logging an informative `[Funes]` line
  ([#59](https://github.com/funes-org/funes/pull/59))
- **Breaking:** dropped support for Rails 7.1 — Rails >= 7.2 is now required
  ([#55](https://github.com/funes-org/funes/pull/55))

### Internal

- CI matrix trimmed to the version extremes and extended to Ruby 4.0
  ([#55](https://github.com/funes-org/funes/pull/55))

## [0.2.1] - 2026-04-17

### Performance

- Transactional projections now reuse the caller's `EventStream` instead of
  re-loading events from the database
  ([#54](https://github.com/funes-org/funes/pull/54))

### Added

- In-process benchmark suite with a Docker-based CI job
  ([#51](https://github.com/funes-org/funes/pull/51))

### Documentation

- The DSL is presented as a first-class concept in the README and guides
  ([#53](https://github.com/funes-org/funes/pull/53))
- Restored the three-tier consistency model section in the README
  ([#49](https://github.com/funes-org/funes/pull/49))
- Added the "Testing projections" guide; removed the self-hosted YARD docs in
  favor of the guides site
  ([#46](https://github.com/funes-org/funes/pull/46),
  [#47](https://github.com/funes-org/funes/pull/47))

## [0.2.0] - 2026-03-25

The first minor release: bi-temporal support, a Rails-friendlier event API,
persisted materialization models, and the guides site.

### Changed

- **Breaking:** renamed `EventStream#append!` to `append`, following Rails
  conventions (a new `append!` with different semantics was reintroduced
  in 0.2.2)
- **Breaking:** reorganized the temporal API — `as_of` moved from
  `EventStream.for` to `projected_with`, was removed from
  `Projection#process_events` and `materialize!`, and interpretation blocks
  should now prefer `event.occurred_at`
- Events now record `created_at` (recording time, set with `Time.current`),
  distinct from `occurred_at` (occurrence time)
  ([#39](https://github.com/funes-org/funes/pull/39),
  [#40](https://github.com/funes-org/funes/pull/40))

### Added

- Bi-temporal event streams: replay state by occurrence time (`at:`) and by
  recording time (`as_of:`) ([#41](https://github.com/funes-org/funes/pull/41))
- `EventStream#projected_with` to materialize any projection on demand from a
  stream ([#37](https://github.com/funes-org/funes/pull/37))
- Event meta-information with validation support
  (`Funes::EventMetainformation`)
  ([#28](https://github.com/funes-org/funes/pull/28))
- Explicit event rejection inside interpretation blocks via
  `Event#interpretation_errors`; ineffective errors added in transactional or
  async projections are logged as warnings
  ([#35](https://github.com/funes-org/funes/pull/35))
- `Funes::Inspection` — rich `#inspect`/`pp` output for events, masking
  sensitive attributes via `Rails.application.config.filter_parameters`
  ([#38](https://github.com/funes-org/funes/pull/38))
- Rails-friendly event interface: `Event#persisted?`, `Event#to_params`, and
  the `Funes::Routable` module for URL generation
  ([#27](https://github.com/funes-org/funes/pull/27))
- `materialization_table` generator and documented schema requirements for
  persisted materialization models
  ([#31](https://github.com/funes-org/funes/pull/31))
- Projection test helpers for asserting initial and final states
  ([#34](https://github.com/funes-org/funes/pull/34))
- Guides website ([docs.funes.org](https://docs.funes.org)) with core concepts
  and how-to guides ([#43](https://github.com/funes-org/funes/pull/43),
  [#45](https://github.com/funes-org/funes/pull/45))

### Fixed

- Autoloading of the engine's non-conventional `app/` directories (such as
  `app/event_streams` and `app/projections`)
  ([#24](https://github.com/funes-org/funes/pull/24))
- Table and column names in the install migration template
  ([#25](https://github.com/funes-org/funes/pull/25))
- `EventStream#events` ordering by `occurred_at` when in-session (not yet
  persisted) events are present
  ([#44](https://github.com/funes-org/funes/pull/44))
- Database errors raised inside transactional projections now fail loudly
  instead of being swallowed
  ([#30](https://github.com/funes-org/funes/pull/30))
- ActiveRecord validations run before the upsert in transactional projections
- Generated migrations use the lowest compatible Rails migration version

### Internal

- Test suite overhaul ([#42](https://github.com/funes-org/funes/pull/42)),
  dedicated coverage job with SimpleCov, and multi-version CI with Appraisal
  ([#33](https://github.com/funes-org/funes/pull/33))

## [0.1.1] - 2026-01-08

### Fixed

- Added missing transactional control to `EventStream#append!`

## [0.1.0] - 2026-01-07

Initial public release, published as `funes-rails`.

### Added

- `Funes::Event` — immutable, `ActiveModel`-based events with validations,
  persisted in an append-only entries table (`Funes::EventEntry`)
- `Funes::Projection` — declarative `interpretation_for` DSL deriving state
  from events, materialized in-memory (`ActiveModel`) or persisted
  (`ActiveRecord`)
- `Funes::EventStream` with the three-tier consistency model: consistency
  projection (validates business rules before persisting an event),
  transactional projections (same database transaction), and async projections
  (`ActiveJob` via `PersistProjectionJob`)
- `Funes::ProjectionTestHelper` for testing projections
- `funes:install` generator with the initial migration
- Mountable Rails engine and multi-version API documentation deployment

[Unreleased]: https://github.com/funes-org/funes/compare/v0.2.5...HEAD
[0.2.5]: https://github.com/funes-org/funes/compare/v0.2.4...v0.2.5
[0.2.4]: https://github.com/funes-org/funes/compare/v0.2.3...v0.2.4
[0.2.3]: https://github.com/funes-org/funes/compare/v0.2.2...v0.2.3
[0.2.2]: https://github.com/funes-org/funes/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/funes-org/funes/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/funes-org/funes/releases/tag/v0.2.0
[0.1.1]: https://github.com/funes-org/funes/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/funes-org/funes/releases/tag/v0.1.0

<!-- v0.2.0 links to the tag instead of a compare view: the repository history
     was rewritten after v0.1.1, so the v0.1.x tags share no ancestor with main
     and GitHub cannot render a compare between them. -->
