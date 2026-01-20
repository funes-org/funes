# Event Metainformation

In auditable systems, knowing *what* happened is only part of the story — you also need to know *who* did it and *in what context*. Event metainformation allows you to attach contextual data to every event recorded during a request, such as the acting user, the controller action, or the application version. This enriches your audit trail with the provenance information required for compliance, debugging, and forensic analysis.

## Configuration

Event metainformation is configured in two parts: attributes (via array) and validations (via block DSL).

### Defining Attributes

Define the attributes your application needs:

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [:user_id, :action, :git_version]
end
```

Or in environment files:

```ruby
# config/environments/production.rb
Rails.application.configure do
  config.funes.event_metainformation_attributes = [:user_id, :action, :git_version]
end
```

### Adding Validations

Add validation rules for your attributes using the block DSL:

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [:user_id, :action, :request_id]

  config.event_metainformation_validations do
    validates :user_id, presence: true
    validates :action, presence: true, format: { with: /\A\w+#\w+\z/ }
    validates :request_id, format: { with: /\A[a-f0-9-]+\z/, allow_blank: true }
  end
end
```

Or in environment files:

```ruby
# config/environments/production.rb
Rails.application.configure do
  config.funes.event_metainformation_validations do
    validates :user_id, presence: true
    validates :action, presence: true
  end
end
```

## Supported Validators

The block DSL supports all standard ActiveModel validators including `presence`, `format`, `length`, `numericality`, `inclusion`, `exclusion`, and others. Multiple validators can be combined in a single declaration.

For complete documentation on available validators and their options, see the [ActiveModel Validations guide](https://guides.rubyonrails.org/active_model_basics.html#validations).

## Setting Metainformation

Populate metainformation values in your controllers via a concern:

```ruby
# app/controllers/concerns/trackable_events_on_funes.rb.rb
module TrackableEventsOnFunes
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

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include TrackableEventsOnFunes
end
```

## Validation

When validations are configured, they are automatically checked during event persistence. If the metainformation fails validation, a `Funes::InvalidEventMetainformation` error will be raised.

## Thread Safety

`Funes::EventMetainformation` extends `ActiveSupport::CurrentAttributes`, which provides thread-isolated attribute storage. Each request gets its own isolated set of values, automatically reset between requests. This makes it safe to use in multi-threaded environments like Puma or Sidekiq.

## Example: Complete Configuration

```ruby
# config/initializers/funes.rb
Funes.configure do |config|
  config.event_metainformation_attributes = [
    :user_id,
    :user_email,
    :action,
    :git_version,
    :request_id,
    :ip_address
  ]

  config.event_metainformation_validations do
    validates :user_id, presence: true
    validates :user_email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
    validates :action, presence: true, format: { with: /\A\w+#\w+\z/ }
    validates :request_id, presence: true, format: { with: /\A[a-f0-9-]+\z/ }
  end
end
```

```ruby
# app/controllers/concerns/trackable_events_on_funes.rb
module TrackableEventsOnFunes
  extend ActiveSupport::Concern

  included do
    before_action :set_event_metainformation
  end

  private

    def set_event_metainformation
      Funes::EventMetainformation.user_id = current_user&.id
      Funes::EventMetainformation.user_email = current_user&.email
      Funes::EventMetainformation.action = "#{controller_name}##{action_name}"
      Funes::EventMetainformation.git_version = ENV["GIT_VERSION"]
      Funes::EventMetainformation.request_id = request.request_id
      Funes::EventMetainformation.ip_address = request.remote_ip
    end
end
```
