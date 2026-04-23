module Examples::Deposit
  class HistoryProjection < Funes::Projection
    materialization_model Examples::Deposit::History
    persists_per_change

    interpretation_for Examples::DepositEvents::Created do |state, creation_event, _at|
      state.assign_attributes(balance: creation_event.value)
      state
    end

    interpretation_for Examples::DepositEvents::Withdrawn do |state, withdrawn_event, _at|
      previous_balance = state.balance || 0
      state.assign_attributes(balance: previous_balance - withdrawn_event.amount)
      state
    end
  end
end
