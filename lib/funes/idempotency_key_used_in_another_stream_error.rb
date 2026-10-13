module Funes
  # Raised by `append!` when the idempotency key was already used by an event in another
  # event stream.
  #
  # Idempotency keys are unique across all streams, so the typical cause is a redelivery that
  # was routed to a freshly minted `idx` while the original delivery already created the
  # stream. The event's class and attributes are not compared: the caller is on the wrong
  # stream, and `idx` names the right one. Plain `append` raises nothing; it returns the event
  # unpersisted with an error on `event.errors[:base]` that names that stream.
  #
  # @example Redelivery of a creation message
  #   begin
  #     DebtEventStream.for(SecureRandom.uuid)
  #                    .append!(Debt::Issued.new(principal: 100), idempotency_key: "kafka:debts:0:4411")
  #   rescue Funes::IdempotencyKeyUsedInAnotherStreamError => e
  #     e.idx # => the idx of the debt the first delivery created
  #   end
  class IdempotencyKeyUsedInAnotherStreamError < IdempotencyKeyConflictError; end
end
