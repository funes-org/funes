module SpecFailingExamples::PersistMaterializationModelWith
  # A non-ActiveRecord materialization model that always fails validation when reached.
  # `record_call!` would mutate process-local state if the projection ever delegated to it,
  # so the tests can assert it was never invoked.
  class FailingMaterializationModel
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::AttributeAssignment

    class << self
      attr_accessor :persist_calls
    end
    self.persist_calls = 0

    attribute :idx, :string
    attribute :balance, :decimal

    validates :balance, numericality: { greater_than: 1_000_000 }

    def persist!
      self.class.persist_calls += 1
      true
    end
  end

  class FailingOnValidationProjection < Funes::Projection
    materialization_model FailingMaterializationModel
    persist_materialization_model_with :persist!

    interpretation_for Examples::DepositEvents::Created do |state, event, _at|
      state.assign_attributes(balance: event.value) # always below the validation threshold
      state
    end
  end

  class DepositEventStreamWithValidationFailure < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection FailingOnValidationProjection
  end
end
