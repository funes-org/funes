module Funes
  # Raised when attempting to persist an event with invalid metainformation.
  #
  # This error is raised during Event#persist! when the configured
  # EventMetainformation validations fail. The event is not persisted.
  #
  # @example Handling invalid metainformation
  #   begin
  #     event.persist!(idx, version)
  #   rescue Funes::InvalidEventMetainformation => e
  #     Rails.logger.error "Invalid metainformation: #{e.message}"
  #   end
  #
  # @see Funes::EventMetainformation
  # @see Funes::Configuration#event_metainformation_validations
  class InvalidEventMetainformation < StandardError; end
end
