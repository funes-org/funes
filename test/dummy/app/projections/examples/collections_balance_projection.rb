module Examples
  class CollectionsBalanceProjection < Funes::Projection
    set_materialization_model DebtCollectionsProjection

    set_interpretation_for Debt::Issued do |_state, event|
      { outstanding_balance: event.value,
        issuance_date: event.at,
        last_payment_date: nil }
    end

    set_interpretation_for Debt::Paid do |state, event|
      outstanding_balance = state[:outstanding_balance] - event.value - event.discount
      raise Funes::LedToInvalidState, "The outstanding balance can't be negative" if outstanding_balance.negative?

      state.merge({ outstanding_balance:, last_payment_date: event.at  })
    end

    set_interpretation_for Debt::AdjustedByIndex do |state, event|
      outstanding_balance = (state[:outstanding_balance] * (1 + event.rate)).round(2)
      state.merge({ outstanding_balance: })
    end
  end
end
