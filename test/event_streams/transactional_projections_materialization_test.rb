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
    set_materialization_model DummyMaterializationModel
  end

  class TransactionalProjection < Funes::Projection
    set_materialization_model DummyMaterializationModel
  end

  class SecondTransactionalProjection < Funes::Projection
    set_materialization_model DummyMaterializationModel
  end

  describe "when there is a single transactional projections in place" do
    class EventStreamWithSingleTransactionalProjection < Funes::EventStream
      set_transactional_projection TransactionalProjection
    end

    it "calls the persistence job (`perform_now`) for the projection" do
      event_stream_instance = EventStreamWithSingleTransactionalProjection.with_id("my-identifier")
      mock = Minitest::Mock.new
      mock.expect(:call, true, [ event_stream_instance, TransactionalProjection ])

      Funes::PersistProjectionJob.stub(:perform_now, mock) do
        event = DummyEvent.new(value: 42)
        event_stream_instance.append!(event)
      end

      assert_mock mock
    end
  end

  describe "when there are multiple transactional projections in place" do
    class EventStreamWithMultipleTransactionalProjection < Funes::EventStream
      set_transactional_projection TransactionalProjection
      set_transactional_projection SecondTransactionalProjection
    end

    it "calls the persistence job (`perform_now`) for each transactional projection" do
      event_stream_instance = EventStreamWithMultipleTransactionalProjection.with_id("my-identifier")
      mock = Minitest::Mock.new
      mock.expect(:call, true, [ event_stream_instance, TransactionalProjection ])
      mock.expect(:call, true, [ event_stream_instance, SecondTransactionalProjection ])

      Funes::PersistProjectionJob.stub(:perform_now, mock) do
        event = DummyEvent.new(value: 42)
        event_stream_instance.append!(event)
      end

      assert_mock mock
    end
  end
end
