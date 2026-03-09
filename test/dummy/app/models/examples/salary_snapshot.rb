module Examples
  class SalarySnapshot
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :amount, :decimal
    attribute :effective_since, :date
    attribute :days_in_effect, :integer
  end
end
