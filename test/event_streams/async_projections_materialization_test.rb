require "test_helper"
require "minitest/spec"
require "minitest/mock"

class AsyncProjectionsMaterializationTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class DummyEvent < Funes::Event
    attribute :value, :integer
  end

  class DummyMaterializationModel
    include ActiveModel::Model
  end

  class HypotheticalConsistencyProjection < Funes::Projection
    set_materialization_model DummyMaterializationModel
  end

  class AsyncProjection < Funes::Projection
    set_materialization_model DummyMaterializationModel
  end

  class SecondAsyncProjection < Funes::Projection
    set_materialization_model DummyMaterializationModel
  end

  describe "when there is a single async projection in place" do
    describe "when no options are provided in its configuration" do
      class EventStreamWithSingleAsyncProjection < Funes::EventStream
        add_async_projection AsyncProjection
      end

      it "enqueues the persistence job (`perform_later`) with no job options" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
        perform_later_mock = Minitest::Mock.new.expect(:perform_later, true, [ "my-identifier", AsyncProjection, as_of_time ])
        set_mock = Minitest::Mock.new.expect(:call, perform_later_mock, [ {} ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithSingleAsyncProjection.with_id("my-identifier", as_of_time).append!(event)
          end
        end

        assert_mock set_mock
        assert_mock perform_later_mock
      end
    end

    describe "when options are provided in its configuration" do
      class EventStreamWithSingleAsyncProjectionAndOptions < Funes::EventStream
        add_async_projection(AsyncProjection, queue:      :default,
                                              wait_until: Time.current.tomorrow.midnight)
      end

      it "correctly configures the persistence job options through the `set` method" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
        set_mock = Minitest::Mock.new.expect(:call, Minitest::Mock.new.expect(:perform_later, true, [ "my-identifier", AsyncProjection, as_of_time ]),
                                             [ { queue: :default, wait_until: Time.current.tomorrow.midnight } ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithSingleAsyncProjectionAndOptions.with_id("my-identifier", as_of_time).append!(event)
          end
        end

        assert_mock set_mock
      end

      it "enqueues the persistence job sending the correct parameters to `perform_later`" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
        perform_later_mock = Minitest::Mock.new.expect(:perform_later, true, [ "my-identifier", AsyncProjection, as_of_time ])
        set_mock = Minitest::Mock.new.expect(:call, perform_later_mock, [ { queue: :default,
                                                                            wait_until: Time.current.tomorrow.midnight } ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithSingleAsyncProjectionAndOptions.with_id("my-identifier", as_of_time).append!(event)
          end
        end

        assert_mock perform_later_mock
      end
    end
  end

  describe "when there are two or more async projections in place with different job options" do
    class StreamWithMultipleAsyncProjections < Funes::EventStream
      add_async_projection AsyncProjection, queue: :urgent
      add_async_projection SecondAsyncProjection, queue: :default
    end

    it "correctly configures the persistence job options through the `set` method for each projection" do
      as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
      set_mock = Minitest::Mock.new
      set_mock.expect(:call, Minitest::Mock.new.expect(:perform_later, true, [ "my-identifier", AsyncProjection, as_of_time ]),
                      [ { queue: :urgent } ])
      set_mock.expect(:call, Minitest::Mock.new.expect(:perform_later, true, [ "my-identifier", SecondAsyncProjection, as_of_time ]),
                      [ { queue: :default } ])

      travel_to(as_of_time) do
        Funes::PersistProjectionJob.stub(:set, set_mock) do
          event = DummyEvent.new(value: 42)
          StreamWithMultipleAsyncProjections.with_id("my-identifier", as_of_time).append!(event)
        end
      end

      assert_mock set_mock
    end

    it "enqueues the persistence job (`perform_later`) with the correct options for each projection" do
      as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
      perform_later_mock = Minitest::Mock.new
      perform_later_mock.expect(:perform_later, true, [ "my-identifier", AsyncProjection, as_of_time ])
      perform_later_mock.expect(:perform_later, true, [ "my-identifier", SecondAsyncProjection, as_of_time ])
      set_stub = Minitest::Mock.new
                               .expect(:call, perform_later_mock, [ { queue: :urgent } ])
                               .expect(:call, perform_later_mock, [ { queue: :default } ])

      travel_to(as_of_time) do
        Funes::PersistProjectionJob.stub(:set, set_stub) do
          event = DummyEvent.new(value: 42)
          StreamWithMultipleAsyncProjections.with_id("my-identifier", as_of_time).append!(event)
        end
      end

      assert_mock perform_later_mock
    end
  end
end
