module Examples
  class DebtCollectionsProjection < Funes::Projection
    materialization_model Examples::DebtCollection

    initial_state do
      Examples::DebtCollection.new
    end

    interpretation_for Examples::Debt::Issued do |state, event|
      state.assign_attributes(outstanding_balance: event.value,
                              issuance_date: event.at,
                              status: :unpaid)
      state
    end

    interpretation_for Examples::Debt::Paid do |state, event|
      new_outstanding_balance = state.outstanding_balance - event.value - event.discount
      state.assign_attributes(outstanding_balance: new_outstanding_balance,
                              last_payment_date: event.at,
                              status: new_outstanding_balance.zero? ? :paid : :unpaid)
      state
    end

    interpretation_for Examples::Debt::AdjustedByIndex do |state, event|
      outstanding_balance = (state.outstanding_balance * (1 + event.rate)).round(2)
      state.assign_attributes(outstanding_balance:)
      state
    end
  end
end
