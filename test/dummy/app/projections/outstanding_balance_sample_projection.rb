class OutstandingBalanceSampleProjection < Funes::Projection
  set_interpretation_for "Debt::Issued" do |_state, event|
    event[:value]
  end

  set_interpretation_for "Debt::Paid" do |state, event|
    value, discount = event.values_at(:value, :discount)
    new_state = state - value - discount
    raise "Unprocessable: led the state to a negative outstanding balance" if new_state.negative?
    raise "Unprocessable: led the state to a negative outstanding balance" if new_state.negative?

    new_state
  end

  set_interpretation_for "Debt::AdjustedByIndex" do |state, event|
    (state * (1 + event[:rate])).round(2)
  end
end
