module Examples
  class DebtSnapshotProjection < Funes::Projection
    not_ignore_unknown_event_types

    set_initial_state do
      Examples::DebtVirtualSnapshot.new
    end

    set_interpretation_for Examples::Debt::Issued do |state, event|
      state.assign_attributes(issued_value: event.value,
                              outstanding_balance: event.value,
                              issued_at: event.at)
      state
    end

    set_interpretation_for Examples::Debt::Paid do |state, event|
      outstanding_balance = state.outstanding_balance - event.value - event.discount
      state.assign_attributes(outstanding_balance:,
                              last_payment_at: event.at)
      state
    end

    set_interpretation_for Examples::Debt::AdjustedByIndex do |state, event|
      outstanding_balance = (state.outstanding_balance * (1 + event.rate)).round(2)
      state.assign_attributes(outstanding_balance:)
      state
    end
  end
end
