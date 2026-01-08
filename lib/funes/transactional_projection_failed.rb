module Funes
  # Raised when a transactional projection fails due to a database constraint violation.
  #
  # This error wraps database-level errors (like NOT NULL violations, unique constraint
  # violations, etc.) that occur during the persistence of a transactional projection.
  # When this happens, the entire transaction (including the event) is rolled back.
  #
  # @example Handling projection failures
  #   stream = OrderEventStream.for("order-123")
  #   event = stream.append!(Order::Placed.new(total: 99.99))
  #
  #   if event.errors[:base].present?
  #     # The projection failed and transaction was rolled back
  #     Rails.logger.error "Projection failed: #{event.errors.full_messages}"
  #   end
  class TransactionalProjectionFailed < StandardError; end
end
