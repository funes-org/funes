module SpecFailingExamples::PersistMaterializationModelWith
  # Raised by RaisingOnPersistMaterializationModel#persist! to simulate a custom persistence sink
  # that fails at write time (e.g., object storage unreachable, filesystem read-only, third-party
  # API rejection). Funes should let this exception propagate unchanged.
  class PersistFailureError < StandardError; end

  # A non-ActiveRecord materialization model whose validation always passes but whose persistence
  # step always raises. Use this fixture to exercise the path where the framework delegates to the
  # custom persist method and the method itself fails — distinct from the validation-gate path
  # covered by FailingMaterializationModel.
  class RaisingOnPersistMaterializationModel
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :idx, :string
    attribute :balance, :decimal

    def persist!
      raise PersistFailureError, "simulated persistence sink failure for idx=#{idx}"
    end
  end

  class RaisingOnPersistProjection < Funes::Projection
    materialization_model RaisingOnPersistMaterializationModel
    persist_materialization_model_with :persist!

    interpretation_for Examples::DepositEvents::Created do |state, event, _at|
      state.assign_attributes(balance: event.value)
      state
    end
  end

  class DepositEventStreamWithPersistFailure < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection RaisingOnPersistProjection
  end
end
