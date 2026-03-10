require "test_helper"
require "minitest/spec"

module Examples::DepositEvents
  class CreatedTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL

    describe "validations" do
      it "is valid with value and at" do
        event = Created.new(value: 100.0, effective_date: Date.today)
        assert event.valid?
      end

      describe "value" do
        it "is invalid without value" do
          event = Created.new(effective_date: Date.today)
          refute event.valid?
          assert_includes event.errors[:value], "can't be blank"
        end

        it "is invalid when value is zero" do
          event = Created.new(value: 0, effective_date: Date.today)
          refute event.valid?
          assert_includes event.errors[:value], "must be greater than 0"
        end

        it "is invalid when value is negative" do
          event = Created.new(value: -50, effective_date: Date.today)
          refute event.valid?
          assert_includes event.errors[:value], "must be greater than 0"
        end
      end

      describe "at" do
        it "is invalid without at" do
          event = Created.new(value: 100.0)
          refute event.valid?
          assert_includes event.errors[:effective_date], "can't be blank"
        end
      end
    end

    describe "attributes" do
      it "casts value as decimal" do
        event = Created.new(value: "250.50", effective_date: Date.today)
        assert_equal BigDecimal("250.50"), event.value
      end

      it "casts at as date" do
        event = Created.new(value: 100, effective_date: "2024-01-15")
        assert_equal Date.new(2024, 1, 15), event.effective_date
      end
    end
  end
end
