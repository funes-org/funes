module Examples
  class DebtVirtualSnapshot
    include ActiveModel::Model
    include ActiveModel::Attributes
    include ActiveModel::AttributeAssignment

    attribute :issued_value, :float
    validates :issued_value, presence: true, numericality: { greater_than: 0 }

    attribute :outstanding_balance, :float
    validates :outstanding_balance, presence: true, numericality: { greater_than_or_equal_to: 0 }

    attribute :issued_at, :date
    validates :issued_at, presence: true

    attribute :last_payment_at, :date
  end
end
