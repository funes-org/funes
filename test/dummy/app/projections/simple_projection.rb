class SimpleProjection < Funes::Projection
  set_interpretation_for Test::Start do |_state, event|
    event.value
  end

  set_interpretation_for Test::Add do |state, event|
    state + event.value
  end
end
