module Funes
  # Test helper for testing projections in isolation.
  #
  # Include this module in your test classes to access helper methods that allow you to test
  # individual projection interpretations without needing to process entire event streams.
  #
  # @example Include in your test
  #   class InventorySnapshotProjectionTest < ActiveSupport::TestCase
  #     include Funes::ProjectionTestHelper
  #
  #     test "receiving items increases quantity on hand" do
  #       initial_state = InventorySnapshot.new(quantity_on_hand: 10)
  #       event = Inventory::ItemReceived.new(quantity: 5, unit_cost: 9.99)
  #
  #       result = interpret_event_based_on(InventorySnapshotProjection, event, initial_state)
  #
  #       assert_equal 15, result.quantity_on_hand
  #     end
  #   end
  module ProjectionTestHelper
    # Test a single event interpretation in isolation.
    #
    # This method extracts and executes a single interpretation block from a projection,
    # allowing you to test how specific events transform state without processing entire
    # event streams.
    #
    # @param [Class<Funes::Projection>] projection_class The projection class being tested.
    # @param [Funes::Event] event_instance The event to interpret.
    # @param [ActiveModel::Model, ActiveRecord::Base] previous_state The state before applying the event.
    # @param [Time] at The temporal reference point. Defaults to Time.current.
    # @return [ActiveModel::Model, ActiveRecord::Base] The new state after applying the interpretation.
    #
    # @example Test a single interpretation
    #   initial_state = OrderSnapshot.new(total: 100)
    #   event = Order::ItemAdded.new(amount: 50)
    #
    #   result = interpret_event_based_on(OrderSnapshotProjection, event, initial_state)
    #
    #   assert_equal 150, result.total
    #
    # @example Test with validations
    #   state = InventorySnapshot.new(quantity_on_hand: 5)
    #   event = Inventory::ItemShipped.new(quantity: 10)
    #
    #   result = interpret_event_based_on(InventorySnapshotProjection, event, state)
    #
    #   assert_equal -5, result.quantity_on_hand
    #   refute result.valid?
    def interpret_event_based_on(projection_class, event_instance, previous_state, at = Time.current)
      projection_class.instance_variable_get(:@interpretations)[event_instance.class]
                      .call(previous_state, event_instance, at)
    end

    # Test an initial_state block in isolation.
    #
    # This method extracts and executes the initial_state block from a projection,
    # allowing you to test how the projection builds its starting state without
    # processing entire event streams.
    #
    # @param [Class<Funes::Projection>] projection_class The projection class being tested.
    # @param [Time] at The temporal reference point. Defaults to Time.current.
    # @return [ActiveModel::Model, ActiveRecord::Base] The initial state produced by the projection.
    #
    # @example Test initial state construction
    #   result = build_initial_state_based_on(InventorySnapshotProjection)
    #
    #   assert_equal 0, result.quantity_on_hand
    #
    # @example Test with a specific timestamp
    #   at = Time.new(2023, 5, 10)
    #
    #   result = build_initial_state_based_on(InventorySnapshotProjection, at)
    #
    #   assert_equal at, result.created_at
    def build_initial_state_based_on(projection_class, at = Time.current)
      projection_class.instance_variable_get(:@interpretations)[:init]
                      .call(projection_class.instance_variable_get(:@materialization_model), at)
    end

    # Test a final_state block in isolation.
    #
    # This method extracts and executes the final_state block from a projection,
    # allowing you to test how the projection transforms state after all event
    # interpretations have been applied.
    #
    # @param [Class<Funes::Projection>] projection_class The projection class being tested.
    # @param [ActiveModel::Model, ActiveRecord::Base] previous_state The state before applying the final transformation.
    # @param [Time] at The temporal reference point. Defaults to Time.current.
    # @return [ActiveModel::Model, ActiveRecord::Base] The final state after applying the transformation.
    #
    # @example Test final state transformation
    #   state = OrderSnapshot.new(total: 100, item_count: 3)
    #
    #   result = apply_final_state_based_on(OrderSnapshotProjection, state)
    #
    #   assert_equal 33.33, result.average_item_price
    #
    # @example Test with a specific timestamp
    #   state = InventorySnapshot.new(quantity_on_hand: 10)
    #   at = Time.new(2023, 5, 10)
    #
    #   result = apply_final_state_based_on(InventorySnapshotProjection, state, at)
    #
    #   assert_equal at, result.finalized_at
    def apply_final_state_based_on(projection_class, previous_state, at = Time.current)
      projection_class.instance_variable_get(:@interpretations)[:final]
                      .call(previous_state, at)
    end
  end
end
