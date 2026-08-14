# Writing Funes Guides

The goal is warm professionalism: encouraging without being casual, authoritative without being distant.

## Voice & Tone

- Address the reader directly with **"you"**, and use **"we/let's"** to make them a participant
- Use active voice. Make Funes the agent, not a passive system
- Short, direct sentences for instructions. Longer sentences only when explaining *why* something works as it does
- Occasional enthusiasm is welcome ("Pretty cool!") but keep it sparse

## Simplified Technical English (STE)

The guides follow the writing rules of ASD-STE100 (Simplified Technical
English), adapted for software documentation. This section is self-contained —
apply it directly, without consulting the specification. Where a rule here
conflicts with Voice & Tone, this section wins, except for the deliberate
deviations listed at the end.

### Words

- **One word, one meaning.** Pick one term per concept and use it in every
  guide. When a term is defined in one guide, other guides use the same term
  and link to it.
- **Use the canonical phrasing** for Funes concepts. `TERMINOLOGY.md` at the
  repository root lists the wrong/right pairs and why — check it before
  writing, and add a row whenever a review corrects a concept's phrasing.
- **Use a word in only one part of speech.** If "record" is the verb for
  storing events, do not also use "a record" as a noun for a database row —
  say "row" instead.
- **Prefer the short, common word.** Common substitutions:

  | Avoid | Use |
  |---|---|
  | utilize | use |
  | in order to | to |
  | prior to | before |
  | subsequently, consequently | then, so |
  | additionally, furthermore | also |
  | approximately | about |
  | modification | change |
  | functionality | feature, function |
  | leverage | use |
  | perform (an action) | do, run |

- **Technical names are always allowed**, whatever their form: Rails, Gemfile,
  `event_entries`, JSON, "optimistic locking", class and method names. Treat
  domain vocabulary (event, stream, projection, materialization) the same way.

### Verbs

- **Active voice, always.** "Funes stores all events in one table", never
  "events are stored". If a passive slips in, name the agent and flip it.
- **Simple tenses only**: simple present ("the migration creates"), simple
  past ("the event occurred"), and future with "will". Avoid perfect and
  progressive forms: "has created" → "creates" or "created"; "is running" →
  "runs".
- **Avoid `-ing` verb forms** when a finite verb or infinitive works: "after
  installing the gem" → "after you install the gem"; "for querying events" →
  "to query events". (`-ing` words that are established technical names —
  "locking", "logging", "streaming" — are fine.)
- **Headings use the imperative or a noun phrase**: "Install the gem" or
  "Installation", not "Installing the gem".

### Sentences

- **Instructions: 20 words maximum. Descriptions: 25 words maximum.** Count
  the words; if over, split the sentence. A code identifier counts as one word.
- **One instruction per sentence.** "Open the file and check the columns" is
  two instructions — split it, unless the actions happen together.
- **Keep subject–verb–object order.** Put a condition before its instruction:
  "If you use Postgres, the migration uses `jsonb`."
- **Use a vertical list** when a sentence enumerates three or more items or
  steps, unless every item is only one or two words — short series stay
  inline.
- **Use articles.** Write "Generate the migration", not "Generate migration".
- **Write "that" after reporting verbs**: "Make sure that the migration ran."
- **No vague references.** "This creates a migration" → "This command creates
  a migration". Every "this", "it", "these" must have an obvious noun, or gets
  the noun repeated.

### Paragraphs

- **Six sentences maximum**, one topic per paragraph.
- **The first sentence states the topic.** Supporting detail follows it.
- Present new or complex information in steps: concept first, then the
  example, then the confirmation (this matches the Guide Structure flow below).

### Instructions, warnings, and notes

- **Write instructions as commands**: "Run the migration", not "You should run
  the migration" or "The migration should be run".
- **Put a warning before the step it protects**, start it with a command, and
  give the reason: "Do not rename the `event_entries` table — Funes resolves
  it by name."
- **Notes give information, not commands.** If a note tells the reader to do
  something, it is an instruction — move it into the body text.

### Noun clusters

- **Three nouns in a row, maximum.** Break longer clusters with "of", "for",
  or a hyphen: "event stream version conflict" → "a version conflict in the
  event stream".
- Hyphenate a cluster when it modifies another noun: "read-only projection".

### Deliberate deviations from STE

The guides keep these house-voice traits even though strict STE forbids them:

- **"You" and "we/let's"** for direct address and participation (per Voice &
  Tone).
- **Contractions** ("you'll", "don't") — they carry the warm register.
- **Sparse enthusiasm** ("Pretty cool!") — at most one per guide.
- **Explanatory "why" sentences** may run longer than 25 words when splitting
  them would break the reasoning — but treat this as the exception.

### Review checklist for a page

When applying STE to an existing page, scan for, in order:

1. Passive voice ("is stored", "are created", "it is recommended").
2. Sentences over the 20/25-word limits.
3. `-ing` verb forms that are not technical names (including headings).
4. Vague "this/it/these" without a noun.
5. Noun clusters of four or more nouns.
6. Perfect/progressive tenses and wordy substitutable phrases (table above).
7. Paragraphs over six sentences or with more than one topic.

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

## What to Avoid

- Passive constructions ("it is recommended that...") — say who does what
- Explaining the same concept twice across different guides — link instead
- Skipping the "why" — readers need to understand motivation, not just steps
- Over-engineering examples — keep them minimal and focused on the concept being taught
