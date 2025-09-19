module Examples
  class OutstandingBalanceProjection < Funes::Projection
    set_interpretation_for Debt::Issued do |_state, event|
      event.value
    end

    set_interpretation_for Debt::Paid do |state, event|
      value, discount = event.values_at(:value, :discount)
      new_state = state - value - discount
      raise Funes::LedToInvalidState, "The outstanding balance can't be negative" if new_state.negative?

      new_state
    end

    set_interpretation_for Debt::AdjustedByIndex do |state, event|
      (state * (1 + event.rate)).round(2)
    end
  end
end
