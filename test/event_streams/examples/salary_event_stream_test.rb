require "test_helper"
require "minitest/spec"

# Scenario: Sally's salary history has two events.
#
#   Jan 1  (recorded Jan 1):  salary set to $6,000, effective Jan 1
#   Mar 15 (recorded Mar 15): salary raised to $6,500, effective Feb 15  ← retroactive
#
# This creates a classic bitemporal situation: on Mar 15, the system learns that
# Sally's salary had already changed on Feb 15. Queries made "as of Mar 1" (before
# the raise was recorded) see a different history than queries made today.
module Examples
  class SalaryEventStreamTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL

    setup do
      @idx = "sally-#{SecureRandom.uuid}"

      travel_to Time.new(2025, 1, 1, 9, 0, 0) do
        Examples::SalaryEventStream
          .for(@idx)
          .append(Examples::Salary::Set.new(amount: 6000,
                                            effective_date: Date.new(2025, 1, 1)))
      end

      travel_to Time.new(2025, 3, 15, 9, 0, 0) do
        Examples::SalaryEventStream
          .for(@idx)
          .append(Examples::Salary::Set.new(amount: 6500,
                                            effective_date: Date.new(2025, 2, 15)))
      end
    end

    describe "actual-time queries (at:)" do
      it "reflects only the salary effective before the given date" do
        result = Examples::SalaryEventStream.for(@idx)
                   .projected_with(Examples::SalarySnapshotProjection, at: Time.new(2025, 2, 10))

        assert_equal 6000, result.amount
        assert_equal Date.new(2025, 1, 1), result.effective_since
      end

      it "includes a retroactive event once its effective date falls within the query window" do
        result = Examples::SalaryEventStream.for(@idx)
                   .projected_with(Examples::SalarySnapshotProjection, at: Time.new(2025, 2, 20))

        assert_equal 6500, result.amount
        assert_equal Date.new(2025, 2, 15), result.effective_since
      end
    end

    describe "full bitemporal queries (as_of: + at:)" do
      it "excludes a retroactive event when as_of predates its recording" do
        # The Feb 15 raise was recorded on Mar 15 — as_of Mar 1 means the system doesn't know about it yet.
        # Even though the raise is effective on Feb 15, which is before the at: query date,
        # the system hadn't recorded it yet as of Mar 1.
        result = Examples::SalaryEventStream.for(@idx)
                   .projected_with(Examples::SalarySnapshotProjection,
                                   as_of: Time.new(2025, 3, 1),
                                   at: Time.new(2025, 2, 20))

        assert_equal 6000, result.amount
      end

      it "includes a retroactive event when as_of is after its recording" do
        result = Examples::SalaryEventStream.for(@idx)
                   .projected_with(Examples::SalarySnapshotProjection,
                                   as_of: Time.new(2025, 4, 1),
                                   at: Time.new(2025, 2, 20))

        assert_equal 6500, result.amount
      end
    end

    describe "temporal reference in projection interpretation" do
      it "computes days_in_effect from the effective date to the query at: date" do
        result = Examples::SalaryEventStream.for(@idx)
                   .projected_with(Examples::SalarySnapshotProjection, at: Time.new(2025, 2, 20))

        assert_equal 5, result.days_in_effect  # Feb 15 → Feb 20 = 5 days
      end

      it "leaves days_in_effect nil when no at: is given" do
        result = Examples::SalaryEventStream.for(@idx)
                   .projected_with(Examples::SalarySnapshotProjection)

        assert_nil result.days_in_effect
      end
    end

    describe "actual_time_attribute extraction" do
      it "uses effective_date as occurred_at" do
        stream = Examples::SalaryEventStream.for("test-#{SecureRandom.uuid}")
        event = stream.append(Examples::Salary::Set.new(amount: 5000, effective_date: Date.new(2025, 6, 1)))

        assert_equal Date.new(2025, 6, 1).beginning_of_day, event.occurred_at
      end

      it "returns an invalid event when effective_date is nil (caught by event validation before stream)" do
        stream = Examples::SalaryEventStream.for("test-#{SecureRandom.uuid}")
        event = stream.append(Examples::Salary::Set.new(amount: 5000, effective_date: nil))

        assert_not event.persisted?
        assert event.own_errors.of_kind?(:effective_date, :blank)
      end

      it "raises MissingActualTimeAttributeError when the event does not have the configured attribute" do
        unrelated_event = Class.new(Funes::Event) { attribute :amount, :decimal }
        stream = Examples::SalaryEventStream.for("test-#{SecureRandom.uuid}")

        assert_raises Funes::MissingActualTimeAttributeError do
          stream.append(unrelated_event.new(amount: 5000))
        end
      end
    end
  end
end
