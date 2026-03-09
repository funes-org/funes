module Examples
  class SalarySnapshotProjection < Funes::Projection
    materialization_model Examples::SalarySnapshot

    # `at` here is event.occurred_at (the effective date of this particular salary change)
    interpretation_for Examples::Salary::Set do |state, event, at|
      state.assign_attributes(amount: event.amount,
                              effective_since: at&.to_date)
      state
    end

    # `at` here is the query-level temporal reference from projected_with(at:)
    final_state do |state, at|
      if at && state.effective_since
        state.assign_attributes(days_in_effect: (at.to_date - state.effective_since).to_i)
      end
      state
    end
  end
end
