# Simplified Technical English (STE)

Prose in this repository follows the writing rules of ASD-STE100 (Simplified
Technical English), adapted for software documentation. This document is
self-contained — apply it directly, without consulting the specification.
Where a rule here conflicts with the Voice & Tone section of
`guides/CLAUDE.md`, this document wins, except for the deliberate deviations
listed at the end.

## Words

- **One word, one meaning.** Pick one term per concept and use it in every
  guide. When a term is defined in one guide, other guides use the same term
  and link to it.
- **Use the canonical phrasing** for Funes concepts. `TERMINOLOGY.md` (next to
  this file) lists the wrong/right pairs and why — check it before writing,
  and add a row whenever a review corrects a concept's phrasing.
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

## Verbs

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

## Sentences

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

## Paragraphs

- **Six sentences maximum**, one topic per paragraph.
- **The first sentence states the topic.** Supporting detail follows it.
- Present new or complex information in steps: concept first, then the
  example, then the confirmation (this matches the Guide Structure flow in
  `guides/CLAUDE.md`).

## Instructions, warnings, and notes

- **Write instructions as commands**: "Run the migration", not "You should run
  the migration" or "The migration should be run".
- **Put a warning before the step it protects**, start it with a command, and
  give the reason: "Do not rename the `event_entries` table — Funes resolves
  it by name."
- **Notes give information, not commands.** If a note tells the reader to do
  something, it is an instruction — move it into the body text.

## Noun clusters

- **Three nouns in a row, maximum.** Break longer clusters with "of", "for",
  or a hyphen: "event stream version conflict" → "a version conflict in the
  event stream".
- Hyphenate a cluster when it modifies another noun: "read-only projection".

## Deliberate deviations from STE

The guides keep these house-voice traits even though strict STE forbids them:

- **"You" and "we/let's"** for direct address and participation (per the
  Voice & Tone section of `guides/CLAUDE.md`).
- **Contractions** ("you'll", "don't") — they carry the warm register.
- **Sparse enthusiasm** ("Pretty cool!") — at most one per guide.
- **Explanatory "why" sentences** may run longer than 25 words when splitting
  them would break the reasoning — but treat this as the exception.

## Review checklist for a page

When applying STE to an existing page, scan for, in order:

1. Passive voice ("is stored", "are created", "it is recommended").
2. Sentences over the 20/25-word limits.
3. `-ing` verb forms that are not technical names (including headings).
4. Vague "this/it/these" without a noun.
5. Noun clusters of four or more nouns.
6. Perfect/progressive tenses and wordy substitutable phrases (table above).
7. Paragraphs over six sentences or with more than one topic.
