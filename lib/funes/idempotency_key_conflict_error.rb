module Funes
  # Raised by `append!` when the idempotency key was already used in the same event stream
  # by an event of a different class or with different attributes.
  #
  # A repeated key with the same event class and attributes is a duplicate, not a conflict:
  # nothing is written and the event reports `duplicate?`. A conflict means the caller reused
  # the key for a different fact. Plain `append` raises nothing; it returns the event
  # unpersisted with an error on `event.errors[:base]`.
  #
  # The error exposes the stored entry that holds the key, so the caller can tell which event
  # took it. {Funes::IdempotencyKeyUsedInAnotherStreamError} is a subclass of this error.
  #
  # @example
  #   stream.append!(Debt::PaymentReceived.new(amount: 30), idempotency_key: "charge:ch_1")
  #   stream.append!(Debt::PaymentReceived.new(amount: 50), idempotency_key: "charge:ch_1")
  #   # => raises Funes::IdempotencyKeyConflictError
  class IdempotencyKeyConflictError < StandardError
    # @return [String] The idempotency key that was already used.
    attr_reader :idempotency_key

    # @return [String] The entity identifier of the event stream that holds the key.
    attr_reader :idx

    # @return [String] The class name of the event that holds the key.
    attr_reader :klass

    # @return [Integer] The version, within its stream, of the event that holds the key.
    attr_reader :version

    # @!visibility private
    def initialize(message = nil, entry: nil)
      super(message)
      return unless entry

      @idempotency_key = entry.idempotency_key
      @idx = entry.idx
      @klass = entry.klass
      @version = entry.version
    end
  end
end
