---
title: Getting started
layout: default
nav_order: 2
---

# Getting started
{: .no_toc }

You'll add Funes to a Rails application and generate a migration that creates the table where Funes stores events. There are two short steps.

## Install the gem

Add Funes to your Gemfile:

```ruby
gem "funes-rails"
```

Then install the gem:

```bash
$ bundle install
```

## Add the events table

Funes stores all events in a single table called `event_entries`. Generate the migration that creates this table:

```bash
$ bin/rails generate funes:install
```

This command creates a migration file under `db/migrate/`. Open the file and you'll see that it sets up the `event_entries` table with the columns Funes needs:

- the event class
- a stream identifier
- the event attributes, as JSON
- a version number, for concurrency control
- two timestamps: `created_at` for when Funes recorded the event, and `occurred_at` for when the event actually happened

{: .note }
On Postgres, the migration uses `jsonb` instead of `json` for the attributes and metainformation columns. The data is the same, but the database can index and query it.

Now run the migration:

```bash
$ bin/rails db:migrate
```

Your events table is ready. Funes will append rows to `event_entries` as soon as you define your first event stream.

## Next steps

- The [Concepts](/concepts/) section explains events, event streams, and projections — the three ideas that form the core of Funes.
- The [Recipes](/recipes/) section shows how to apply these ideas: append events from controllers, interpret them with a historic perspective, ship projections to S3, and more.
