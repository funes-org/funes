# Funes Terminology

Canonical phrasing for Funes concepts, for anyone (human or agent) writing
prose in this repository — guides, README, changelog, code documentation, and
commit messages. Some concepts have one correct phrasing; wrong paraphrases
misdescribe the mechanism. Add a row whenever a review corrects a concept's
phrasing, with a short note on why.

The writing rules in `STE.md` have a narrower reach than this file: they cover
user-facing documentation only. Canonical phrasing binds everywhere.

| Wrong | Right | Why |
|---|---|---|
| query events historically, historical queries, temporal queries | interpret events with a historic perspective | Funes replays events through a projection as of a point in time — an interpretation feature, not a query feature |
| stream of events | event stream | The canonical name of the concept (see `concepts/event-stream.md`) |
| view, read model | projection | The canonical name of the concept (see `concepts/projection.md`) |
| write/push an event | append an event | Appending is the only write operation on an event stream |
