module SpecFailingExamples::TwoTransactionalProjections
  class FailingOnCreateProjection < Funes::Projection
    materialization_model Examples::Deposit::LastActivities

    interpretation_for Examples::DepositEvents::Created do |state, _event, at|
      state.assign_attributes(activity_type: :creation, creation_date: nil, activity_date: nil)
      state
    end
  end

  class DepositEventStream < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection Examples::Deposit::SnapshotProjection
    add_transactional_projection FailingOnCreateProjection
  end
end
