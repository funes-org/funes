require "fileutils"
require "json"

module Examples::Deposit
  class JsonSnapshot
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :idx, :string
    attribute :original_value, :decimal
    attribute :balance, :decimal
    attribute :status, :string
    attribute :created_at, :date

    validates :idx, presence: true
    validates :original_value, numericality: { greater_than: 0 }
    validates :balance, numericality: { greater_than_or_equal_to: 0 }
    validates :status, inclusion: { in: %w[active withdrawn] }

    def save_to_object_storage!
      path = self.class.storage_path_for(idx)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(attributes))
      true
    end

    def self.storage_path_for(idx)
      Rails.root.join("tmp", "deposit_snapshots", "#{idx}.json")
    end
  end
end
