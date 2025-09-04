module Examples
  class DebtSnapshotProjection < Funes::Projection
    raise_on_unknown_events
    # allow_unknown_event_types

    initial_state do |materialization_model|
      Examples::DebtVirtualSnapshot.new
    end

    interpretation_for Examples::Debt::Issued do |state, event|
      state.assign_attributes(issued_value: event.value,
                              outstanding_balance: event.value,
                              issued_at: event.at)
      state
    end

    interpretation_for Examples::Debt::Paid do |state, event|
      outstanding_balance = state.outstanding_balance - event.value - event.discount
      state.assign_attributes(outstanding_balance:,
                              last_payment_at: event.at)
      state
    end

    interpretation_for Examples::Debt::AdjustedByIndex do |state, event|
      outstanding_balance = (state.outstanding_balance * (1 + event.rate)).round(2)
      state.assign_attributes(outstanding_balance:)
      state
    end
  end
end
