class Debt::Paid < Funes::Event
  attribute :value, :float
  attribute :discount, :float
  attribute :at, :date
end
