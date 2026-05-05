module Funes
  # Raised when a projection configured with `persist_materialization_model_with` produces an
  # invalid materialization state.
  #
  # When a projection declares a custom persistence method via `persist_materialization_model_with`,
  # Funes still validates the materialization (via `state.valid?`) before delegating the write.
  # If validation fails, this exception is raised and the custom persist method is *not* invoked.
  #
  # The failed materialization is exposed via `#record`, mirroring the ergonomics of
  # `ActiveRecord::RecordInvalid` — but without coupling the custom-persist path to ActiveRecord.
  # Like any unrescued exception, it propagates out of `materialize!` and rolls back any enclosing
  # `ActiveRecord::Base.transaction`, which is the desired behaviour for transactional projections.
  #
  # @example Handling an invalid materialization state
  #   begin
  #     YourProjection.materialize!(events, "some-id", at: Time.current)
  #   rescue Funes::InvalidMaterializationState => e
  #     Rails.logger.error "Invalid materialization: #{e.message}"
  #     e.record.errors.full_messages # the validation errors on the materialization
  #   end
  #
  # @see Funes::Projection.persist_materialization_model_with
  class InvalidMaterializationState < StandardError
    attr_reader :record

    def initialize(record)
      @record = record
      super("Invalid materialization state: #{record.errors.full_messages.to_sentence}")
    end
  end
end
