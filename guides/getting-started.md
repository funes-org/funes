---
title: Getting started
layout: default
nav_order: 2
---

# Getting started
{: .no_toc }

You'll add Funes to a Rails application and generate a migration that creates the table it uses to store events. Two short steps.

## Installing the gem

Add Funes to your Gemfile:

```ruby
gem "funes-rails"
```

Then install it:

```bash
$ bundle install
```

## Adding the events table

Funes stores all events in a single table called `event_entries`. Generate the migration that creates it:

```bash
$ bin/rails generate funes:install
```

This creates a migration file under `db/migrate/`. Open it and you'll see it sets up the `event_entries` table with the columns Funes needs: the event class, a stream identifier, the event attributes as JSON, a version number for concurrency control, and two timestamps — `created_at` for when the event was recorded and `occurred_at` for when it actually happened.

{: .note }
On Postgres, the migration uses `jsonb` instead of `json` for the attributes and metainformation columns — same data, but indexable and queryable inside the database.

Now run the migration:

```bash
$ bin/rails db:migrate
```

Your events table is ready. Funes will start appending rows to `event_entries` as soon as you define your first event stream.

## Where to next

- The [Concepts](/concepts/) section explains events, streams, and projections — the three ideas Funes is built around.
- The [Recipes](/recipes/) section shows how to apply them: appending from controllers, querying historically, shipping projections to S3, and more.
