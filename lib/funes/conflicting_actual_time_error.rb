module Funes
  # Raised when both an explicit `at:` on `append` and the event's `actual_time_attribute`
  # are present with different values.
  #
  # This is always a bug in the caller's code — there's no valid reason to provide
  # conflicting actual times for the same event.
  #
  # @example
  #   # Given a stream with actual_time_attribute :at
  #   stream.append(Salary::Raised.new(amount: 6500, at: feb_15), at: mar_1)
  #   # => raises Funes::ConflictingActualTimeError
  class ConflictingActualTimeError < StandardError; end
end
