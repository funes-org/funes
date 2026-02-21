require "test_helper"
require "minitest/spec"

class BitemporalTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  class SalarySet < Funes::Event
    attribute :amount, :decimal
    attribute :at, :datetime
  end

  class SalaryRaised < Funes::Event
    attribute :amount, :decimal
    attribute :at, :datetime
  end

  class SalarySetWithDate < Funes::Event
    attribute :amount, :decimal
    attribute :at, :date
  end

  class EventWithoutAt < Funes::Event
    attribute :amount, :decimal
  end

  salary_state = Class.new do
    include ActiveModel::Model
    include ActiveModel::Attributes

    attribute :salary, :decimal
  end

  salary_projection = Class.new(Funes::Projection) do
    materialization_model salary_state

    interpretation_for SalarySet do |state, event, _at|
      state.assign_attributes(salary: event.amount)
      state
    end

    interpretation_for SalaryRaised do |state, event, _at|
      state.assign_attributes(salary: event.amount)
      state
    end

    interpretation_for SalarySetWithDate do |state, event, _at|
      state.assign_attributes(salary: event.amount)
      state
    end
  end

  stream_with_actual_time = Class.new(Funes::EventStream) do
    actual_time_attribute :at
  end

  stream_without_actual_time = Class.new(Funes::EventStream)

  describe "appending events with explicit at:" do
    it "stores occurred_at matching the at: value" do
      idx = "salary-at-explicit-#{SecureRandom.uuid}"
      stream = stream_without_actual_time.for(idx)
      feb_15 = Time.new(2025, 2, 15, 12, 0, 0)

      event = stream.append(SalarySet.new(amount: 6000), at: feb_15)

      assert event.persisted?
      assert_equal feb_15, event.occurred_at
    end

    it "defaults occurred_at to created_at when at: is not provided" do
      idx = "salary-at-default-#{SecureRandom.uuid}"
      stream = stream_without_actual_time.for(idx)

      event = stream.append(SalarySet.new(amount: 6000))

      assert event.persisted?
      assert_equal event.created_at, event.occurred_at
    end
  end

  describe "actual_time_attribute auto-extraction" do
    it "uses the event attribute as occurred_at when configured" do
      idx = "salary-attr-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)
      feb_15 = Time.new(2025, 2, 15, 12, 0, 0)

      event = stream.append(SalarySet.new(amount: 6000, at: feb_15))

      assert event.persisted?
      assert_equal feb_15, event.occurred_at
    end

    it "uses event attribute when at: on append is nil" do
      idx = "salary-attr-nil-at-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)
      feb_15 = Time.new(2025, 2, 15, 12, 0, 0)

      event = stream.append(SalaryRaised.new(amount: 6500, at: feb_15))

      assert_equal feb_15, event.occurred_at
    end

    it "falls back to created_at when event attribute is nil" do
      idx = "salary-attr-fallback-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)

      event = stream.append(SalarySet.new(amount: 6000, at: nil))

      assert_equal event.created_at, event.occurred_at
    end

    it "uses explicit at: when both at: and event attribute agree" do
      idx = "salary-attr-agree-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)
      feb_15 = Time.new(2025, 2, 15, 12, 0, 0)

      event = stream.append(SalarySet.new(amount: 6000, at: feb_15), at: feb_15)

      assert_equal feb_15, event.occurred_at
    end
  end

  describe "ConflictingActualTimeError" do
    it "raises when at: and event attribute have different values" do
      idx = "salary-conflict-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)
      feb_15 = Time.new(2025, 2, 15, 12, 0, 0)
      mar_1 = Time.new(2025, 3, 1, 12, 0, 0)

      assert_raises Funes::ConflictingActualTimeError do
        stream.append(SalarySet.new(amount: 6000, at: feb_15), at: mar_1)
      end
    end

    it "does not raise when at: and event attribute match" do
      idx = "salary-no-conflict-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)
      feb_15 = Time.new(2025, 2, 15, 12, 0, 0)

      assert_nothing_raised do
        stream.append(SalarySet.new(amount: 6000, at: feb_15), at: feb_15)
      end
    end
  end

  describe "MissingActualTimeAttributeError" do
    it "raises when event does not have the configured attribute" do
      idx = "salary-missing-attr-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)

      assert_raises Funes::MissingActualTimeAttributeError do
        stream.append(EventWithoutAt.new(amount: 6000))
      end
    end
  end

  describe "projected_with at: filtering" do
    it "includes only events where occurred_at <= at" do
      idx = "salary-projected-at-#{SecureRandom.uuid}"
      stream = stream_without_actual_time.for(idx)

      stream.append(SalarySet.new(amount: 6000), at: Time.new(2025, 1, 1))
      stream.append(SalaryRaised.new(amount: 6500), at: Time.new(2025, 2, 15))
      stream.append(SalaryRaised.new(amount: 7000), at: Time.new(2025, 4, 1))

      result = stream_without_actual_time.for(idx).projected_with(salary_projection, at: Time.new(2025, 3, 1))

      assert_equal 6500, result.salary
    end

    it "includes all events when at: is nil" do
      idx = "salary-projected-no-at-#{SecureRandom.uuid}"
      stream = stream_without_actual_time.for(idx)

      stream.append(SalarySet.new(amount: 6000), at: Time.new(2025, 1, 1))
      stream.append(SalaryRaised.new(amount: 7000), at: Time.new(2025, 4, 1))

      result = stream_without_actual_time.for(idx).projected_with(salary_projection)

      assert_equal 7000, result.salary
    end
  end

  describe "full bitemporal queries (as_of + at)" do
    it "filters by both record time and actual time" do
      idx = "salary-bitemporal-#{SecureRandom.uuid}"

      # Jan 1: record salary at $6,000 (occurred Jan 1)
      travel_to Time.new(2025, 1, 1, 12, 0, 0) do
        stream_without_actual_time.for(idx).append(SalarySet.new(amount: 6000), at: Time.new(2025, 1, 1))
      end

      # Mar 15: record retroactive raise to $6,500 that happened Feb 15
      travel_to Time.new(2025, 3, 15, 12, 0, 0) do
        stream_without_actual_time.for(idx).append(SalaryRaised.new(amount: 6500), at: Time.new(2025, 2, 15))
      end

      # Query: "What did the system think Sally's salary was on Feb 20,
      #          given only what it knew as of Mar 1?"
      # The raise (recorded Mar 15) is NOT included — as_of=Mar 1 excludes it.
      stream = stream_without_actual_time.for(idx, Time.new(2025, 3, 1))
      result = stream.projected_with(salary_projection, at: Time.new(2025, 2, 20))

      assert_equal 6000, result.salary
    end

    it "includes retroactive events when as_of is after recording time" do
      idx = "salary-bitemporal-include-#{SecureRandom.uuid}"

      # Jan 1: record salary at $6,000
      travel_to Time.new(2025, 1, 1, 12, 0, 0) do
        stream_without_actual_time.for(idx).append(SalarySet.new(amount: 6000), at: Time.new(2025, 1, 1))
      end

      # Mar 15: record retroactive raise to $6,500 that happened Feb 15
      travel_to Time.new(2025, 3, 15, 12, 0, 0) do
        stream_without_actual_time.for(idx).append(SalaryRaised.new(amount: 6500), at: Time.new(2025, 2, 15))
      end

      # Query: "Given everything the system currently knows, what was salary on Feb 20?"
      # The raise IS included — system knows about it now.
      stream = stream_without_actual_time.for(idx)
      result = stream.projected_with(salary_projection, at: Time.new(2025, 2, 20))

      assert_equal 6500, result.salary
    end

    it "orders events by occurred_at for correct projection" do
      idx = "salary-ordering-#{SecureRandom.uuid}"

      # Record a bonus for Mar 10 first (on Feb 20)
      travel_to Time.new(2025, 2, 20, 12, 0, 0) do
        stream_without_actual_time.for(idx).append(SalarySet.new(amount: 6000), at: Time.new(2025, 1, 1))
        stream_without_actual_time.for(idx).append(SalaryRaised.new(amount: 7000), at: Time.new(2025, 3, 10))
      end

      # Then record a raise for Feb 15 later (on Mar 15)
      travel_to Time.new(2025, 3, 15, 12, 0, 0) do
        stream_without_actual_time.for(idx).append(SalaryRaised.new(amount: 6500), at: Time.new(2025, 2, 15))
      end

      # Events in occurred_at order: Set(Jan1) -> Raised(Feb15) -> Raised(Mar10)
      # Last event wins, so salary should be 7000
      stream = stream_without_actual_time.for(idx)
      result = stream.projected_with(salary_projection)

      assert_equal 7000, result.salary
    end
  end

  describe "Date coercion" do
    it "coerces Date to beginning_of_day when passed as at: on append" do
      idx = "salary-date-coerce-#{SecureRandom.uuid}"
      stream = stream_without_actual_time.for(idx)

      event = stream.append(SalarySet.new(amount: 6000), at: Date.new(2025, 2, 15))

      assert event.persisted?
      assert_equal Date.new(2025, 2, 15).beginning_of_day, event.occurred_at
    end

    it "coerces Date from event attribute via actual_time_attribute" do
      idx = "salary-date-attr-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)

      event = stream.append(SalarySetWithDate.new(amount: 6000, at: Date.new(2025, 2, 15)))

      assert event.persisted?
      assert_equal Date.new(2025, 2, 15).beginning_of_day, event.occurred_at
    end

    it "does not raise conflict when Date and Time represent the same point" do
      idx = "salary-date-time-match-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)
      date_val = Date.new(2025, 2, 15)
      time_val = date_val.beginning_of_day

      assert_nothing_raised do
        stream.append(SalarySetWithDate.new(amount: 6000, at: date_val), at: time_val)
      end
    end

    it "raises conflict when Date and Time represent different points" do
      idx = "salary-date-time-conflict-#{SecureRandom.uuid}"
      stream = stream_with_actual_time.for(idx)

      assert_raises Funes::ConflictingActualTimeError do
        stream.append(SalarySetWithDate.new(amount: 6000, at: Date.new(2025, 2, 15)), at: Time.new(2025, 3, 1))
      end
    end
  end
end
