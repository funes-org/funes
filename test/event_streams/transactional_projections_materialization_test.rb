require "test_helper"
require "minitest/spec"
require "minitest/mock"

class TransactionalProjectionsMaterializationTest < ActiveSupport::TestCase
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

  class TransactionalProjection < Funes::Projection
    materialization_model DummyMaterializationModel
  end

  class SecondTransactionalProjection < Funes::Projection
    materialization_model DummyMaterializationModel
  end

  describe "when there is a single transactional projections in place" do
    class EventStreamWithSingleTransactionalProjection < Funes::EventStream
      add_transactional_projection TransactionalProjection
    end

    it "calls the persistence job (`perform_now`) for the projection" do
      event_stream_instance = EventStreamWithSingleTransactionalProjection.for("my-identifier")
      event_creation_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
      mock = Minitest::Mock.new
      mock.expect(:call, true, [ "my-identifier", TransactionalProjection, event_creation_time, event_creation_time ])

      travel_to(event_creation_time) do
        Funes::PersistProjectionJob.stub(:perform_now, mock) do
          event = DummyEvent.new(value: 42)
          event_stream_instance.append(event)
        end
      end

      assert_mock mock
    end
  end

  describe "when there are multiple transactional projections in place" do
    class EventStreamWithMultipleTransactionalProjection < Funes::EventStream
      add_transactional_projection TransactionalProjection
      add_transactional_projection SecondTransactionalProjection
    end

    it "calls the persistence job (`perform_now`) for each transactional projection" do
      event_stream_instance = EventStreamWithMultipleTransactionalProjection.for("my-identifier")
      event_creation_time = Time.zone.local(2026, 1, 1, 12, 0, 0)
      mock = Minitest::Mock.new
      mock.expect(:call, true, [ "my-identifier", TransactionalProjection, event_creation_time, event_creation_time ])
      mock.expect(:call, true, [ "my-identifier", SecondTransactionalProjection, event_creation_time, event_creation_time ])

      travel_to(event_creation_time) do
        Funes::PersistProjectionJob.stub(:perform_now, mock) do
          event = DummyEvent.new(value: 42)
          event_stream_instance.append(event)
        end
      end

      assert_mock mock
    end
  end
end
