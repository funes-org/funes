module Examples::Deposit
  class LastActivityProjection < Funes::Projection
    materialization_model Examples::Deposit::LastActivities

    interpretation_for Examples::DepositEvents::Created do |state, _event, at|
      state.assign_attributes(activity_type: :creation, creation_date: at, activity_date: at)
      state
    end

    interpretation_for Examples::DepositEvents::Withdrawn do |state, _event, at|
      state.assign_attributes(activity_type: :withdraw, activity_date: at)
      state
    end
  end
end
