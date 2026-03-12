module Funes
  # Raised when an event stream declares `actual_time_attribute` but the appended event
  # does not have that attribute.
  #
  # This catches configuration mismatches early — if a stream expects events to carry
  # an actual time attribute, every event appended to it must define that attribute.
  #
  # @example
  #   class SalaryEventStream < Funes::EventStream
  #     actual_time_attribute :effective_date
  #   end
  #
  #   # Appending an event without an :effective_date attribute:
  #   stream.append(EventWithoutEffectiveDate.new)
  #   # => raises Funes::MissingActualTimeAttributeError
  class MissingActualTimeAttributeError < StandardError; end
end
