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
    # @param [Time, nil] as_of Optional timestamp for temporal logic. Defaults to Time.current.
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
    def interpret_event_based_on(projection_class, event_instance, previous_state, as_of = Time.current)
      projection_class.instance_variable_get(:@interpretations)[event_instance.class]
                      .call(previous_state, event_instance, as_of)
    end
  end
end
