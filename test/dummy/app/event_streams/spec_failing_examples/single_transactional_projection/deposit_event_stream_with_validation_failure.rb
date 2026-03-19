module SpecFailingExamples::SingleTransactionalProjection
  class FailingOnValidationProjection < Funes::Projection
    materialization_model Examples::Deposit::LastActivities

    interpretation_for Examples::DepositEvents::Created do |state, _event, at|
      state.assign_attributes(activity_type: :creation,
                              creation_date: at.to_date,
                              activity_date: at.to_date - 1) # violates activity_date_not_before_creation_date AR validation
      state
    end
  end

  class DepositEventStreamWithValidationFailure < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection FailingOnValidationProjection
  end
end
