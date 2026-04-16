module Bench
  module StreamSeeder
    DEPTHS = [1, 5, 10, 25, 50, 100].freeze
    INITIAL_VALUE = 1_000_000
    WITHDRAWAL_AMOUNT = 1
    CONTRACT_DATE = Date.new(2025, 1, 1)

    module_function

    def seed(depth:, prefix: "bench")
      idx = "#{prefix}-depth-#{depth}-#{SecureRandom.hex(4)}"
      stream = Examples::DepositEventStream.for(idx)

      stream.append(
        Examples::DepositEvents::Created.new(
          value: INITIAL_VALUE,
          effective_date: CONTRACT_DATE
        )
      )

      (depth - 1).times do |i|
        stream.append(
          Examples::DepositEvents::Withdrawn.new(
            amount: WITHDRAWAL_AMOUNT,
            effective_date: CONTRACT_DATE + (i + 1).days
          )
        )
      end

      idx
    end

    def seed_all(depths: DEPTHS, prefix: "bench")
      depths.each_with_object({}) do |depth, map|
        map[depth] = seed(depth: depth, prefix: prefix)
      end
    end

    def cleanup!
      Funes::EventEntry.delete_all
      Examples::Deposit::Snapshot.delete_all
      Examples::Deposit::LastActivities.delete_all
    end
  end
end
