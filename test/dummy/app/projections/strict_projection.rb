class StrictProjection < Funes::Projection
  not_ignore_unknow_event_types

  set_interpretation_for "Test::Start" do |_state, event|
    event[:value]
  end
end
