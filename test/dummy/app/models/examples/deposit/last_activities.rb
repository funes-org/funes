module Examples::Deposit
  class LastActivities < ApplicationRecord
    self.table_name = "deposit_last_activities"
    self.primary_key = :idx # this is important to have a proper behavior on #find method
    enum :activity_type, { creation: 0, withdraw: 1 }
  end
end
