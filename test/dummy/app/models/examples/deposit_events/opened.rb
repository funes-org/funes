module Examples::DepositEvents
  class Opened < Funes::Event
    references :customer, class_name: "Examples::Customer"

    attribute :value, :decimal
    attribute :effective_date, :date

    validates :value, presence: true, numericality: { greater_than: 0 }
  end
end
