module Examples::Deposit
  class Consistency
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :original_value, :decimal
    validates :original_value, presence: true, numericality: { greater_than: 0 }

    attribute :balance, :decimal
    validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  end
end
