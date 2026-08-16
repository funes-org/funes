# CLAUDE.md

Guidance for Claude Code (and other coding agents) working in this repository.
For writing guides content, see `guides/CLAUDE.md`.

## Prose style

Two documents at the repository root govern prose, and they reach different
files. Read both before you write or edit anything they cover.

- **`TERMINOLOGY.md`** lists the canonical phrasing for Funes concepts. Use it
  in every piece of prose you write here: guides, README, changelog, code
  documentation, and commit messages. A concept keeps one name everywhere.
- **`STE.md`** carries the Simplified Technical English writing rules. They
  apply to user-facing documentation — the guides, the README, and the
  changelog. Code documentation, commit messages, and instruction files like
  this one are out of scope.

For the guides, `guides/CLAUDE.md` adds structure and voice rules on top of
both.

### Review checklist

Repeated here so that it reaches you wherever you work in the repository, not
only under `guides/`. When you write or change any prose that `STE.md` covers,
scan it for, in order:

1. Passive voice ("is stored", "are created", "it is recommended").
2. Sentences over the 20/25-word limits.
3. `-ing` verb forms that are not technical names (including headings).
4. Vague "this/it/these" without a noun.
5. Noun clusters of four or more nouns.
6. Perfect/progressive tenses and wordy substitutable phrases.
7. Paragraphs over six sentences or with more than one topic.

`STE.md` stays the canonical source: it carries the rule behind each item, the
word-substitution table that item 6 refers to, and the deliberate deviations.
Read it when an item needs a judgment call. When this list changes, change it
in `STE.md` first.

The README does not follow `STE.md` yet. Bring it in line in a change of its
own; do not assume its current prose is a model to copy.

In `CHANGELOG.md`, both documents apply only to entries for versions greater
than 0.3.0 (the `## [Unreleased]` section and future releases). Never rewrite
the entries of released versions up to and including 0.3.0 — they are
historical records.

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
