module Funes
  # Raised when an event stream declares `actual_time_attribute` but the appended event
  # does not have that attribute.
  #
  # This catches configuration mismatches early — if a stream expects events to carry
  # an actual time attribute, every event appended to it must define that attribute.
  #
  # @example
  #   class SalaryEventStream < Funes::EventStream
  #     actual_time_attribute :at
  #   end
  #
  #   # Appending an event without an :at attribute:
  #   stream.append(EventWithoutAt.new)
  #   # => raises Funes::MissingActualTimeAttributeError
  class MissingActualTimeAttributeError < StandardError; end
end
