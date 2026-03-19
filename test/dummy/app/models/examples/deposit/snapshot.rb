module Examples::Deposit
  class Snapshot < ApplicationRecord
    self.table_name = "deposits"
    self.primary_key = :idx # this is important to have a proper behavior on #find method
    enum :status, { active: 0, withdrawn: 1 }
  end
end
