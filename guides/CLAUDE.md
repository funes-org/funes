# Writing Funes Guides

The goal is warm professionalism: encouraging without being casual, authoritative without being distant.

## Voice & Tone

- Address the reader directly with **"you"**, and use **"we/let's"** to make them a participant
- Use active voice. Make Funes the agent, not a passive system
- Short, direct sentences for instructions. Longer sentences only when explaining *why* something works as it does
- Occasional enthusiasm is welcome ("Pretty cool!") but keep it sparse

## Simplified Technical English (STE)

The guides follow the writing rules of ASD-STE100 (Simplified Technical
English), adapted for software documentation. The full rule set — words,
verbs, sentences, paragraphs, noun clusters, deliberate deviations, and the
review checklist for a page — lives in `STE.md` at the repository root,
next to `TERMINOLOGY.md` (the canonical phrasing for Funes concepts). Read
both before you write or edit a page. Where an STE rule conflicts with Voice
& Tone above, STE wins, except for the deviations listed in `STE.md`.

## Guide Structure

Every page with multiple sections follows the same layout:

```markdown
---
title: <Page title>
layout: default
parent: <Parent>
nav_order: <N>
---

# <Page title>
{: .no_toc }

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

<First paragraph of content — open with the thesis or the framing,
not a "what you'll learn" preamble.>
```

Don't lead with an "After reading this guide, you will know..." line. Open with the framing or thesis directly; the page title and the section headings already set expectations.

Sections follow this flow:
1. **Concept** — explain what something is in plain terms before showing code
2. **Example** — show how to use it, with file path comments and terminal prompts
3. **Confirmation** — show the result (output, generated SQL, browser behavior)

Build concepts progressively. Each section should make sense on its own but also build on what came before.

## Code Examples

- Always introduce a code block with a sentence explaining what it does
- Include file path as a comment on the first line when relevant: `# app/models/order.rb`
- Prefix terminal commands with `$`
- Show expected output separately after the command
- Cross-link to other guides rather than repeating explanations: "You can learn more about projections in the [Projections guide]"

## Terms & Definitions

Introduce technical terms with a short, accessible definition the first time they appear. After that, use them freely. Do not maintain a glossary — define terms in context.

## Prerequisites

State assumptions upfront. If the guide requires knowledge of another concept, say so at the top and link to it.

## Notes & Warnings

Use the just-the-docs `note` callout for important asides. Reserve warnings for things that could cause real confusion or data loss.

```markdown
{: .note }
Funes does not recommend using non-primary key columns named `id`.
```

For warnings, use the same syntax with `{: .warning }`.

## Check the Links Before You Finish

Never close out a change to the guides until every link on the pages you
touched resolves. Heading renames are the usual culprit: permalinks come from
filenames and survive a rename, but in-page anchors come from heading text, so
a reworded heading silently breaks every cross-link that points at it.

Run this check as the last step of any guides change:

1. Build the site — `bundle exec rake guides:serve` regenerates `_site/`.
2. Resolve every markdown link on the pages you changed: internal pages,
   external URLs, and the `#anchor` on both kinds.
3. Match an internal anchor against the `id` attribute on the built page under
   `_site/`, not against the heading text you remember writing.
4. When you rename a heading, grep the whole `guides/` tree for the old anchor
   and update each link that points at it.

A repository-wide edit — a style pass, a terminology change — needs the check
over every page, not only the ones whose diff you can recall.

## What to Avoid

- Passive constructions ("it is recommended that...") — say who does what
- Explaining the same concept twice across different guides — link instead
- Skipping the "why" — readers need to understand motivation, not just steps
- Over-engineering examples — keep them minimal and focused on the concept being taught
