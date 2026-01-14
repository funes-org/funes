module Funes
  # A module that overrides `to_param` to return `idx` for URL generation.
  #
  # Include this module in any materialization model that has an `idx` attribute.
  # This works with both persistent (ActiveRecord) and virtual (ActiveModel) materializations,
  # allowing them to work seamlessly with Rails URL helpers.
  #
  # Persistent materialization models already have the `idx` column by default.
  # Virtual materialization models must manually define the `idx` attribute.
  #
  # @example Include in a persistent materialization model
  #   class DebtCollection < ApplicationRecord
  #     include Funes::Routable
  #   end
  #
  # @example Include in a virtual materialization model (idx must be manually defined)
  #   class DebtVirtualSnapshot
  #     include ActiveModel::Model
  #     include ActiveModel::Attributes
  #     include Funes::Routable
  #
  #     attribute :idx, :string
  #   end
  #
  # @example Using with Rails URL helpers
  #   debt = DebtCollection.find_by(idx: "debt-123")
  #   debt_collection_path(debt) # => "/debt_collections/debt-123"
  module Routable
    # Returns the `idx` attribute as the parameter representation for URL generation.
    #
    # @return [String] The entity identifier (`idx`) used as the URL parameter.
    def to_param
      idx
    end
  end
end
