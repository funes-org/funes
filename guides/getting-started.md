---
title: Getting Started
layout: default
nav_order: 2
---

# Getting Started
{: .no_toc }

After reading this guide, you will know how to add Funes to a Rails application and set up the database it needs to store events.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Installation

Add Funes to your Gemfile:

```ruby
gem "funes-rails"
```

Then run:

```bash
$ bundle install
```

## Setting up the database

Funes stores all events in a single table called `event_entries`. To generate the migration that creates it, run:

```bash
$ bin/rails generate funes:install
```

This creates a migration file under `db/migrate/`. Open it and you'll see it sets up the `event_entries` table with the columns Funes needs: the event class, a stream identifier, the event attributes as JSON, a version number for concurrency control, and two timestamps — `created_at` for when the event was recorded and `occurred_at` for when it actually happened.

Now run the migration:

```bash
$ bin/rails db:migrate
```

Your database is ready. Funes will start appending events to `event_entries` as soon as you define your first event stream.
