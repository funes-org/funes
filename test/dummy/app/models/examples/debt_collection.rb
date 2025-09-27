module Examples
  class DebtCollection < ApplicationRecord
    enum :status, unpaid: 0, paid: 1
  end
end
