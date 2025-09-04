module Funes
  # Raised when attempting to materialize a projection without a configured materialization model.
  #
  # Projections require a materialization model (ActiveModel or ActiveRecord class) to be
  # configured via `materialization_model` before they can be materialized or persisted.
  # This error occurs when calling `materialize!` on a projection that hasn't been properly
  # configured.
  #
  # @example Projection without materialization model (raises error)
  #   class IncompleteProjection < Funes::Projection
  #     interpretation_for OrderPlaced do |state, event, as_of|
  #       # ...
  #     end
  #     # Missing: materialization_model SomeModel
  #   end
  #
  #   # This will raise Funes::UnknownMaterializationModel
  #   IncompleteProjection.materialize!(events, "entity-123", Time.current)
  #
  # @example Properly configured projection
  #   class OrderProjection < Funes::Projection
  #     materialization_model OrderSnapshot
  #
  #     interpretation_for OrderPlaced do |state, event, as_of|
  #       # ...
  #     end
  #   end
  class UnknownMaterializationModel < StandardError; end
end
