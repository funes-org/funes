---
title: Attaching meta information to events
layout: default
parent: Recipes
nav_order: 6
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

This creates `config/initializers/funes.rb` with the `event_metainformation_attributes` and `event_metainformation_validations` blocks ready to uncomment and fill in. The attributes you declare there are exposed on `Funes::EventMetainformation`, an `ActiveSupport::CurrentAttributes` subclass that gives you thread-isolated, per-request storage — automatically reset between requests, and safe under any multithreaded server such as Puma.

## Defining attributes

You configure metainformation in your application's initializer. Start by declaring the attributes you need:

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [:user_id, :action, :git_version]
end
```

These become thread-safe attributes on `Funes::EventMetainformation`, automatically attached to every event persisted during the same request.

{: .note }
Attributes don't take a type — they keep whatever Ruby value you assign. Integers stay integers, strings stay strings, `nil` is allowed. The whole hash is serialized into the event's `meta_info` JSON column when the event lands, so any JSON-compatible value is preserved *ipsis literis*.

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

The block DSL supports all standard `ActiveModel` validators. If metainformation fails validation at the time an event is appended, Funes raises `Funes::InvalidEventMetainformation` and the database transaction is rolled back.

## Setting values per request

Funes doesn't care how the values get set — only that they're in place before an `append` runs. Anything that assigns to `Funes::EventMetainformation` during the request works: a `before_action`, middleware, a service object called from the controller, even a manual assignment inside the action itself.

What follows is one suggestion that fits most Rails apps: populate the attributes at the start of each request from a `before_action`, with a concern keeping the wiring out of `ApplicationController`. Feel free to adapt it to whatever shape your app already uses.

```ruby
# app/controllers/concerns/events_metainformation_attachment.rb
module EventsMetainformationAttachment
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
  include EventsMetainformationAttachment
end
```

Every event appended during that request will carry the values set in this `before_action`.
