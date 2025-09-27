module Examples
  class Debt::Issued < Funes::Event
    attribute :value, :float
    attribute :at, :date

    validates :value, presence: true, numericality: { greater_than: 0 }
    validates :at, presence: true
  end
end
