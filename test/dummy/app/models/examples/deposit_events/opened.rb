module Examples::DepositEvents
  class Opened < Funes::Event
    refers_to :customer, class_name: "Examples::Customer"

    attribute :value, :decimal
    attribute :effective_date, :date

    validates :value, presence: true, numericality: { greater_than: 0 }
  end
end
