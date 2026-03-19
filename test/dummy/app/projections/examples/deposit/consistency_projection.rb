module Examples::Deposit
  class ConsistencyProjection < Funes::Projection
    materialization_model Examples::Deposit::Consistency

    interpretation_for Examples::DepositEvents::Created do |state, creation_event, _at|
      state.assign_attributes(original_value: creation_event.value,
                              balance: creation_event.value)
      state
    end

    interpretation_for Examples::DepositEvents::Withdrawn do |state, withdrawn_event, _at|
      previous_balance = state.balance
      state.assign_attributes(balance: (previous_balance - withdrawn_event.amount))
      state
    end
  end
end
