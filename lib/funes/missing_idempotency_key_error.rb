module Funes
  # Raised when an event stream requires an idempotency key for the appended event
  # (via `requires_idempotency_key` or `requires_idempotency_key_for`) but `append` /
  # `append!` was called without one.
  #
  # This is always a bug in the caller's code, so it is raised by both `append` and
  # `append!` — the quiet contract of `append` does not cover it.
  #
  # @example
  #   class LedgerEventStream < Funes::EventStream
  #     requires_idempotency_key
  #   end
  #
  #   LedgerEventStream.for("ledger-1").append(Ledger::Credited.new(amount: 10))
  #   # => raises Funes::MissingIdempotencyKeyError
  class MissingIdempotencyKeyError < StandardError; end
end
