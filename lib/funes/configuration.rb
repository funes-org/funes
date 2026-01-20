module Funes
  class Configuration
    attr_accessor :event_metainformation_attributes
    attr_reader :event_metainformation_builder

    def initialize
      @event_metainformation_attributes = []
      @event_metainformation_builder = nil
    end

    # Configure EventMetainformation validations using a block-based DSL.
    #
    # @yield Block containing validates calls
    # @return [void]
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
    def event_metainformation_validations(&block)
      if block_given?
        @event_metainformation_builder = EventMetainformationBuilder.new
        @event_metainformation_builder.evaluate(&block)
      end
    end
  end
end
