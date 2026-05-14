module Funes
  # Raised when a projection encounters an event type it doesn't know how to interpret.
  #
  # By default, projections silently ignore unknown events. This error is only raised when
  # a projection is configured with `strict_mode!`, which enforces strict event
  # handling to catch missing interpretation blocks during development.
  #
  # @example Configure a projection to raise on unknown events
  #   class StrictProjection < Funes::Projection
  #     strict_mode!
  #
  #     interpretation_for OrderPlaced do |state, event, _at|
  #       # ...
  #     end
  #   end
  #
  # @example Handling unknown events
  #   begin
  #     projection.process_events(events)
  #   rescue Funes::UnknownEvent => e
  #     Rails.logger.error "Missing interpretation: #{e.message}"
  #   end
  class UnknownEvent < StandardError; end
end
