---
title: Attaching meta information to events
layout: default
parent: Recipes
nav_order: 5
---

# Attaching meta information to events
{: .no_toc }

After reading this guide, you will know how to attach contextual data — such as the acting user and the current request — to every event your application records.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

In auditable systems, knowing *what* happened is only part of the story — you also need to know *who* did it and *in what context*. **Event metainformation** lets you attach that context to every event recorded during a request, enriching your audit trail with the provenance required for compliance, debugging, and forensic analysis.

## Generating the initializer

Funes ships a generator that creates a pre-configured initializer with the metainformation options already commented in:

```bash
$ bin/rails generate funes:initializer
```

This creates `config/initializers/funes.rb` with the `event_metainformation_attributes` and `event_metainformation_validations` blocks ready to uncomment and fill in. The sections below walk through each option.

## Defining attributes

You configure metainformation in your application's initializer. Start by declaring the attributes you need:

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [:user_id, :action, :git_version]
end
```

These become thread-safe attributes on `Funes::EventMetainformation`, automatically attached to every event persisted during the same request.

## Adding validations

Use the `event_metainformation_validations` block to enforce that the required context is always present when an event is recorded:

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [:user_id, :action, :git_version]

  config.event_metainformation_validations do
    validates :user_id, presence: true
    validates :action, presence: true, format: { with: /\A\w+#\w+\z/ }
    validates :git_version, presence: true, format: { with: /\A[a-f0-9]{7,40}\z/ }
  end
end
```

The block DSL supports all standard `ActiveModel` validators. If metainformation fails validation at the time an event is appended, Funes raises `Funes::InvalidEventMetainformation`.

## Setting values per request

Populate metainformation at the start of each request using a `before_action`. A concern keeps this wiring out of `ApplicationController`:

```ruby
# app/controllers/concerns/trackable_events.rb
module TrackableEvents
  extend ActiveSupport::Concern

  included do
    before_action :set_event_metainformation
  end

  private
      def set_event_metainformation
        Funes::EventMetainformation.user_id = current_user&.id
        Funes::EventMetainformation.action = "#{controller_name}##{action_name}"
        Funes::EventMetainformation.git_version = ENV["GIT_VERSION"]
      end
end
```

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include TrackableEvents
end
```

Every event appended during that request will carry the values set in this `before_action`.

> **Note:** `Funes::EventMetainformation` extends `ActiveSupport::CurrentAttributes`, which provides thread-isolated storage that is automatically reset between requests. It is safe to use with any multi-threaded server such as Puma.
