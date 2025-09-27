module Examples
  class Debt::AdjustedByIndex < Funes::Event
    attribute :rate, :float
    attribute :index, :string
    attribute :at, :date
  end
end
