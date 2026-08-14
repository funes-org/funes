# CLAUDE.md

Guidance for Claude Code (and other coding agents) working in this repository.
For writing guides content, see `guides/CLAUDE.md`.

## Prose style

All prose in this repository (README, guides, changelog) uses the canonical
phrasing listed in `TERMINOLOGY.md` and follows the Simplified Technical
English rules in the STE section of `guides/CLAUDE.md`.

In `CHANGELOG.md`, this applies only to entries for versions greater than
0.3.0 (the `## [Unreleased]` section and future releases). Never rewrite the
entries of released versions up to and including 0.3.0 — they are historical
records.

## Changelog

`CHANGELOG.md` strictly follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/):

- Use only the six official categories: **Added**, **Changed**, **Deprecated**,
  **Removed**, **Fixed**, **Security**. No custom sections (no "Documentation",
  "Internal", or "Performance" — performance improvements go under **Changed**).
- An entry belongs in the changelog only if it is notable to *users of the gem*.
  Do **not** add entries for documentation-only changes (README, guides site),
  development tooling (CI, tests, benchmarks, coverage), or refactors with no
  user-observable effect.
- Write entries for humans, in full sentences, and reference the pull request
  (e.g. `([#61](https://github.com/funes-org/funes/pull/61))`).
- Prefix backwards-incompatible entries with `**Breaking:**`.

### During development

Every pull request that makes a user-notable change must add a bullet to the
`## [Unreleased]` section, under the appropriate category (create the category
heading if it doesn't exist yet). Documentation-only PRs leave the changelog
untouched.

### During a release

1. Bump `Funes::VERSION` in `lib/funes/version.rb`. While the gem is at 0.x,
   breaking changes may ship in any release, but they must be flagged
   `**Breaking:**` in the changelog.
2. In `CHANGELOG.md`:
   - Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD` (today's date).
   - Add a fresh, empty `## [Unreleased]` section above it.
   - Update the link references at the bottom of the file: point
     `[Unreleased]` to `compare/vX.Y.Z...HEAD` and add
     `[X.Y.Z]: https://github.com/funes-org/funes/compare/vPREV...vX.Y.Z`.
3. Commit both files together as `Bump version to X.Y.Z`.
4. From the `main` branch of the canonical repository, run
   `bundle exec rake release` (from `bundler/gem_tasks`): it builds the gem,
   creates the `vX.Y.Z` tag, pushes the tag and the commit to the branch's
   remote, and pushes the gem to RubyGems. The `release:guard_canonical_remote`
   task (defined in the `Rakefile`) aborts the release when that remote is not
   `funes-org/funes`, so an accidental release from a fork fails before
   anything is pushed.

Never tag or publish a release whose changelog section is missing or out of
sync with what actually shipped.
