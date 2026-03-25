module Examples::DepositEvents
  class Created < Funes::Event
    attribute :value, :decimal
    attribute :effective_date, :date

    validates :value, presence: true, numericality: { greater_than: 0 }
    validates :effective_date, presence: true
  end
end
