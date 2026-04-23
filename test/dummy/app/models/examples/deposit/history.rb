module Examples::Deposit
  class History < ApplicationRecord
    self.table_name = "deposit_histories"
    self.primary_key = [ :idx, :version ]

    validates :balance, presence: true
  end
end
