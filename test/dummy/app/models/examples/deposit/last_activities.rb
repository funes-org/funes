module Examples::Deposit
  class LastActivities < ApplicationRecord
    self.table_name = "deposit_last_activities"
    self.primary_key = :idx # this is important to have a proper behavior on #find method
    enum :activity_type, { creation: 0, withdraw: 1 }

    validate :activity_date_not_before_creation_date

    private

    def activity_date_not_before_creation_date
      return unless activity_date.present? && creation_date.present?
      errors.add(:activity_date, "cannot be before creation date") if activity_date < creation_date
    end
  end
end
