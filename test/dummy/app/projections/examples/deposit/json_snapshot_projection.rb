module Examples::Deposit
  class JsonSnapshotProjection < Funes::Projection
    materialization_model Examples::Deposit::JsonSnapshot
    persist_with :save_to_object_storage!

    interpretation_for Examples::DepositEvents::Created do |state, event, at|
      state.assign_attributes(original_value: event.value, balance: event.value,
                              created_at: at, status: "active")
      state
    end

    interpretation_for Examples::DepositEvents::Withdrawn do |state, event, _at|
      balance = state.balance - event.amount
      state.assign_attributes(balance: balance, status: balance.zero? ? "withdrawn" : "active")
      state
    end
  end
end
