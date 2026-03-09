module Examples
  class Salary::Set < Funes::Event
    attribute :amount, :decimal
    attribute :effective_date, :date

    validates :amount, presence: true, numericality: { greater_than: 0 }
    validates :effective_date, presence: true
  end
end
