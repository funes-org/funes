module Funes
  # Builder class that collects validation definitions for EventMetainformation
  # using a block-based DSL.
  #
  # @example
  #   Funes.configure do |config|
  #     config.event_metainformation_attributes = [:user_id, :action]
  #
  #     config.event_metainformation_validations do
  #       validates :user_id, presence: true
  #       validates :action, format: { with: /\A\w+#\w+\z/ }
  #     end
  #   end
  #
  class EventMetainformationBuilder
    attr_reader :validations

    def initialize
      @validations = []
    end

    # Define a validation on EventMetainformation.
    #
    # Supports all standard ActiveModel validators:
    # - presence
    # - format
    # - length
    # - numericality
    # - inclusion
    # - exclusion
    # - custom validators
    #
    # @param args [Array] Attribute name(s) and options
    # @param options [Hash] Validation options passed to ActiveModel::Validations
    # @return [void]
    #
    # @example
    #   validates :user_id, presence: true
    #   validates :action, format: { with: /\A\w+#\w+\z/ }
    #   validates :code, presence: true, length: { minimum: 3 }
    def validates(*args, **options)
      @validations << [ args, options ]
    end

    # Evaluate a block in the context of this builder.
    #
    # @yield Block containing validates calls
    # @return [self]
    def evaluate(&block)
      instance_eval(&block)
      self
    end
  end
end
