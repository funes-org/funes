module Examples::Deposit
  class SnapshotProjection < Funes::Projection
    materialization_model Examples::Deposit::Snapshot

    interpretation_for Examples::DepositEvents::Created do |state, creation_event, at|
      state.assign_attributes(original_value: creation_event.value, balance: creation_event.value,
                              created_at: at, status: :active)
      state
    end

    interpretation_for Examples::DepositEvents::Withdrawn do |state, withdrawn_event, _at|
      previous_balance = state.balance
      balance = previous_balance - withdrawn_event.amount
      state.assign_attributes(balance: balance, status: balance.zero? ? :withdrawn : :active)
      state
    end
  end
end
