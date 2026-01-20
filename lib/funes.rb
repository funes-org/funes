require "funes/version"
require "funes/configuration"
require "funes/event_metainformation_builder"
require "funes/invalid_event_metainformation"
require "funes/engine"

# Funes is an event sourcing framework for Ruby on Rails.
#
# Instead of updating state in place, Funes stores immutable events as the source of truth,
# then derives current state by replaying them through projections. This provides complete
# audit trails, temporal queries, and the ability to create multiple read models from the
# same event stream.
#
# ## Core Concepts
#
# - **Events** ({Funes::Event}): Immutable facts representing something that happened
# - **Event Streams** ({Funes::EventStream}): Append-only sequences of events for a specific entity
# - **Projections** ({Funes::Projection}): Transform events into read models (state)
#
# ## Getting Started
#
# 1. Install the gem and run migrations:
#    ```bash
#    $ bin/rails generate funes:install
#    $ bin/rails db:migrate
#    ```
#
# 2. Define your events:
#    ```ruby
#    class Order::Placed < Funes::Event
#      attribute :total, :decimal
#      attribute :customer_id, :string
#      validates :total, presence: true
#    end
#    ```
#
# 3. Define a projection:
#    ```ruby
#    class OrderProjection < Funes::Projection
#      materialization_model OrderSnapshot
#
#      interpretation_for Order::Placed do |state, event, as_of|
#        state.assign_attributes(total: event.total)
#        state
#      end
#    end
#    ```
#
# 4. Create an event stream:
#    ```ruby
#    class OrderEventStream < Funes::EventStream
#      add_transactional_projection OrderProjection
#    end
#    ```
#
# 5. Append events:
#    ```ruby
#    stream = OrderEventStream.for("order-123")
#    event = stream.append(Order::Placed.new(total: 99.99, customer_id: "cust-1"))
#    ```
#
# ## Three-Tier Consistency Model
#
# Funes provides fine-grained control over projection execution:
#
# - **Consistency Projection**: Validates business rules before persisting events
# - **Transactional Projections**: Execute synchronously in the same database transaction
# - **Async Projections**: Execute asynchronously via ActiveJob
#
# @see Funes::Event
# @see Funes::EventStream
# @see Funes::Projection
# @see Funes::ProjectionTestHelper
module Funes
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end
