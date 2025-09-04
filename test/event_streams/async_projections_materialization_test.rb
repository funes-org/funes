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
    materialization_model DummyMaterializationModel
  end

  class AsyncProjection < Funes::Projection
    materialization_model DummyMaterializationModel
  end

  class SecondAsyncProjection < Funes::Projection
    materialization_model DummyMaterializationModel
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
            EventStreamWithSingleAsyncProjection.for("my-identifier", as_of_time).append!(event)
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
            EventStreamWithSingleAsyncProjectionAndOptions.for("my-identifier", as_of_time).append!(event)
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
            EventStreamWithSingleAsyncProjectionAndOptions.for("my-identifier", as_of_time).append!(event)
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
          StreamWithMultipleAsyncProjections.for("my-identifier", as_of_time).append!(event)
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
          StreamWithMultipleAsyncProjections.for("my-identifier", as_of_time).append!(event)
        end
      end

      assert_mock perform_later_mock
    end
  end

  describe "as_of configuration" do
    describe "when as_of is not specified (default behavior)" do
      class EventStreamWithDefaultAsOf < Funes::EventStream
        add_async_projection AsyncProjection
      end

      it "uses last_event_time by default (backward compatibility)" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
        perform_later_mock = Minitest::Mock.new.expect(:perform_later, true, [ "test-id", AsyncProjection, as_of_time ])
        set_mock = Minitest::Mock.new.expect(:call, perform_later_mock, [ {} ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithDefaultAsOf.for("test-id", as_of_time).append!(event)
          end
        end

        assert_mock set_mock
        assert_mock perform_later_mock
      end
    end

    describe "when as_of is :job_time" do
      class EventStreamWithJobTime < Funes::EventStream
        add_async_projection AsyncProjection, as_of: :job_time
      end

      it "passes nil to perform_later (job will use Time.current)" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
        perform_later_mock = Minitest::Mock.new.expect(:perform_later, true, [ "test-id", AsyncProjection, nil ])
        set_mock = Minitest::Mock.new.expect(:call, perform_later_mock, [ {} ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithJobTime.for("test-id", as_of_time).append!(event)
          end
        end

        assert_mock set_mock
        assert_mock perform_later_mock
      end
    end

    describe "when as_of is a proc" do
      class EventStreamWithProcAsOf < Funes::EventStream
        add_async_projection AsyncProjection, as_of: ->(last_event) { last_event.created_at.beginning_of_day }
      end

      it "calls the proc with last_event and uses the returned value" do
        as_of_time = Time.zone.local(2026, 1, 15, 14, 30, 0)
        expected_as_of = as_of_time.beginning_of_day
        perform_later_mock = Minitest::Mock.new.expect(:perform_later, true, [ "test-id", AsyncProjection, expected_as_of ])
        set_mock = Minitest::Mock.new.expect(:call, perform_later_mock, [ {} ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithProcAsOf.for("test-id", as_of_time).append!(event)
          end
        end

        assert_mock set_mock
        assert_mock perform_later_mock
      end
    end

    describe "when as_of proc returns invalid value" do
      class EventStreamWithInvalidProc < Funes::EventStream
        add_async_projection AsyncProjection, as_of: ->(_last_event) { nil }
      end

      it "raises ArgumentError with helpful message" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)

        error = assert_raises(ArgumentError) do
          travel_to(as_of_time) do
            event = DummyEvent.new(value: 42)
            EventStreamWithInvalidProc.for("test-id", as_of_time).append!(event)
          end
        end

        assert_match(/Proc must return a Time object/, error.message)
        assert_match(/got NilClass/, error.message)
        assert_match(/Use :job_time symbol/, error.message)
      end
    end

    describe "when as_of is an invalid strategy" do
      class EventStreamWithInvalidStrategy < Funes::EventStream
        add_async_projection AsyncProjection, as_of: :invalid_strategy
      end

      it "raises ArgumentError with clear message" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)

        error = assert_raises(ArgumentError) do
          travel_to(as_of_time) do
            event = DummyEvent.new(value: 42)
            EventStreamWithInvalidStrategy.for("test-id", as_of_time).append!(event)
          end
        end

        assert_match(/Invalid as_of strategy/, error.message)
        assert_match(/Expected :last_event_time, :job_time, or a Proc/, error.message)
      end
    end

    describe "when as_of is combined with ActiveJob options" do
      class EventStreamWithAsOfAndOptions < Funes::EventStream
        add_async_projection AsyncProjection, as_of: :job_time, queue: :reports, wait: 5.minutes
      end

      it "correctly passes both as_of and ActiveJob options" do
        as_of_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
        perform_later_mock = Minitest::Mock.new.expect(:perform_later, true, [ "test-id", AsyncProjection, nil ])
        set_mock = Minitest::Mock.new.expect(:call, perform_later_mock, [ { queue: :reports, wait: 5.minutes } ])

        travel_to(as_of_time) do
          Funes::PersistProjectionJob.stub(:set, set_mock) do
            event = DummyEvent.new(value: 42)
            EventStreamWithAsOfAndOptions.for("test-id", as_of_time).append!(event)
          end
        end

        assert_mock set_mock
        assert_mock perform_later_mock
      end
    end
  end
end
