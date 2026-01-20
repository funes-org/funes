# Request-scoped metadata storage for events.
#
# EventMetainformation provides thread-isolated attribute storage for contextual
# data that should be attached to events, such as the acting user, controller action,
# or application version. It extends ActiveSupport::CurrentAttributes for automatic
# request isolation and includes ActiveModel::Validations for optional validation rules.
#
# ## Configuration
#
# Attributes are defined via the array configuration, and validations via a block DSL:
#
#   Funes.configure do |config|
#     config.event_metainformation_attributes = [:user_id, :action, :git_version]
#
#     config.event_metainformation_validations do
#       validates :user_id, presence: true
#       validates :action, format: { with: /\A\w+#\w+\z/ }
#     end
#   end
#
# ## Supported Validators
#
# All standard ActiveModel validators are supported:
# - presence
# - format (with regex)
# - length (minimum, maximum, is, in)
# - numericality
# - inclusion / exclusion
# - custom validators
#
# ## Usage
#
# Set values in a controller concern:
#
#   Funes::EventMetainformation.user_id = current_user.id
#   Funes::EventMetainformation.action = "#{controller_name}##{action_name}"
#
# Check validity (when validations are configured):
#
#   Funes::EventMetainformation.valid?
#   Funes::EventMetainformation.errors.full_messages
#
class Funes::EventMetainformation < ActiveSupport::CurrentAttributes
  include ActiveModel::Validations

  class << self
    # Sets up attributes and validations from configuration.
    #
    # This method is called during Rails initialization. It:
    # 1. Defines attributes from the configuration array
    # 2. Applies validations from the DSL block (if present)
    #
    # @return [void]
    def setup_attributes!
      configuration = Funes.configuration

      configuration.event_metainformation_attributes.each do |attr_name|
        attribute attr_name
      end

      apply_validations_from_builder(configuration.event_metainformation_builder)
    end

    private
      # Apply validation definitions from the builder to this class.
      #
      # @param builder [Funes::EventMetainformationBuilder, nil] The builder with validation definitions
      # @return [void]
      def apply_validations_from_builder(builder)
        return unless builder

        builder.validations.each do |args, options|
          validates(*args, **options)
        end
      end
  end
end
