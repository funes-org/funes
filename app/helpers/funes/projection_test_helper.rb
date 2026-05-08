module Funes
  # Test helper for exercising projections in isolation.
  #
  # Include this module in your test class to access methods that interpret a
  # single event, build the initial state, or apply the final state of a
  # projection — without processing an entire event stream.
  #
  # Bind the projection class once with the +projection+ macro and then call
  # {#interpret}, {#initial_state}, or {#final_state} without repeating it.
  #
  # @example Bind the projection at the class level
  #   class InventorySnapshotProjectionTest < ActiveSupport::TestCase
  #     include Funes::ProjectionTestHelper
  #     projection InventorySnapshotProjection
  #
  #     test "receiving items increases quantity on hand" do
  #       state = InventorySnapshot.new(quantity_on_hand: 10)
  #       event = Inventory::ItemReceived.new(quantity: 5, unit_cost: 9.99)
  #
  #       result = interpret(event, given: state)
  #
  #       assert_equal 15, result.quantity_on_hand
  #     end
  #   end
  #
  # @example Override the bound projection per call
  #   interpret(event, given: state, projection: AnotherProjection)
  module ProjectionTestHelper
    extend ActiveSupport::Concern

    included do
      class_attribute :projection_under_test, instance_accessor: false
    end

    class_methods do
      # Binds the projection class exercised by this test class. Subclasses
      # inherit the binding and may override it with another call to
      # +projection+.
      #
      # @param [Class<Funes::Projection>] projection_class
      # @return [void]
      def projection(projection_class)
        self.projection_under_test = projection_class
      end
    end

    # Interprets a single event in isolation and returns the resulting state.
    #
    # If the event carries an +occurred_at+, it takes precedence over +at+ —
    # mirroring how {Funes::Projection} replays persisted events. A +Date+
    # passed as +at+ is coerced to its +beginning_of_day+.
    #
    # @param [Funes::Event] event The event to interpret.
    # @param [ActiveModel::Model, ActiveRecord::Base] given The state before applying the event.
    # @param [Time, Date] at The temporal reference point. Defaults to +Time.current+.
    # @param [Class<Funes::Projection>, nil] projection Overrides the class bound via +projection+.
    # @return [ActiveModel::Model, ActiveRecord::Base] The state after the interpretation.
    #
    # @example
    #   result = interpret(Order::ItemAdded.new(amount: 50), given: OrderSnapshot.new(total: 100))
    #   assert_equal 150, result.total
    def interpret(event, given:, at: Time.current, projection: nil)
      projection_class = resolve_projection(projection)
      coerced_at = coerce_at(at)
      event_at = event.occurred_at || coerced_at
      projection_class.instance_variable_get(:@interpretations)[event.class]
                      .call(given, event, event_at)
    end

    # Builds the initial state of the bound projection.
    #
    # @param [Time, Date] at The temporal reference point. Defaults to +Time.current+.
    # @param [Class<Funes::Projection>, nil] projection Overrides the class bound via +projection+.
    # @return [ActiveModel::Model, ActiveRecord::Base] The state produced by the +initial_state+ block.
    #
    # @example
    #   assert_equal 0, initial_state.quantity_on_hand
    def initial_state(at: Time.current, projection: nil)
      projection_class = resolve_projection(projection)
      projection_class.instance_variable_get(:@interpretations)[:init]
                      .call(projection_class.instance_variable_get(:@materialization_model), coerce_at(at))
    end

    # Applies the final-state transformation of the bound projection.
    #
    # @param [ActiveModel::Model, ActiveRecord::Base] state The state to finalize.
    # @param [Time, Date] at The temporal reference point. Defaults to +Time.current+.
    # @param [Class<Funes::Projection>, nil] projection Overrides the class bound via +projection+.
    # @return [ActiveModel::Model, ActiveRecord::Base] The state after the +final_state+ block.
    #
    # @example
    #   assert_equal 33.33, final_state(OrderSnapshot.new(total: 100, item_count: 3)).average_item_price
    def final_state(state, at: Time.current, projection: nil)
      projection_class = resolve_projection(projection)
      projection_class.instance_variable_get(:@interpretations)[:final]
                      .call(state, coerce_at(at))
    end

    private
      def resolve_projection(explicit)
        explicit || self.class.projection_under_test ||
          raise(ArgumentError,
                "No projection bound. Declare `projection ProjectionClass` in your test class " \
                "or pass `projection:` explicitly.")
      end

      def coerce_at(at)
        at.is_a?(Date) && !at.is_a?(Time) ? at.beginning_of_day : at
      end
  end
end
