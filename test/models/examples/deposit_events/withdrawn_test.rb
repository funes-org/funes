require "test_helper"
require "minitest/spec"

module Examples::DepositEvents
  class WithdrawnTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL

    describe "validations" do
      it "is valid with amount and at" do
        event = Withdrawn.new(amount: 50.0, effective_date: Date.today)
        assert event.valid?
      end

      describe "amount" do
        it "is invalid without amount" do
          event = Withdrawn.new(effective_date: Date.today)
          refute event.valid?
          assert_includes event.errors[:amount], "can't be blank"
        end

        it "is invalid when amount is zero" do
          event = Withdrawn.new(amount: 0, effective_date: Date.today)
          refute event.valid?
          assert_includes event.errors[:amount], "must be greater than 0"
        end

        it "is invalid when amount is negative" do
          event = Withdrawn.new(amount: -10, effective_date: Date.today)
          refute event.valid?
          assert_includes event.errors[:amount], "must be greater than 0"
        end
      end

      describe "effective_date" do
        it "is invalid without at" do
          event = Withdrawn.new(amount: 50.0)
          refute event.valid?
          assert_includes event.errors[:effective_date], "can't be blank"
        end
      end
    end

    describe "attributes" do
      it "casts amount as decimal" do
        event = Withdrawn.new(amount: "75.25", effective_date: Date.today)
        assert_equal BigDecimal("75.25"), event.amount
      end

      it "casts at as date" do
        event = Withdrawn.new(amount: 50, effective_date: "2024-06-30")
        assert_equal Date.new(2024, 6, 30), event.effective_date
      end
    end
  end
end
