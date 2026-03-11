require "test_helper"
require "minitest/spec"

module Examples::Deposit
  class ConsistencyTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL

    describe "validations" do
      it "is valid with original_value and balance" do
        assert Consistency.new(original_value: 10_000, balance: 7_000).valid?
      end

      describe "original_value" do
        it "is invalid without original_value" do
          model = Consistency.new(balance: 7_000)
          refute model.valid?
          assert_includes model.errors[:original_value], "can't be blank"
        end

        it "is invalid when original_value is zero" do
          model = Consistency.new(original_value: 0, balance: 7_000)
          refute model.valid?
          assert_includes model.errors[:original_value], "must be greater than 0"
        end

        it "is invalid when original_value is negative" do
          model = Consistency.new(original_value: -1, balance: 7_000)
          refute model.valid?
          assert_includes model.errors[:original_value], "must be greater than 0"
        end
      end

      describe "balance" do
        it "is invalid without balance" do
          model = Consistency.new(original_value: 10_000)
          refute model.valid?
          assert_includes model.errors[:balance], "can't be blank"
        end

        it "is valid when balance is zero" do
          assert Consistency.new(original_value: 10_000, balance: 0).valid?
        end

        it "is invalid when balance is negative" do
          model = Consistency.new(original_value: 10_000, balance: -1)
          refute model.valid?
          assert_includes model.errors[:balance], "must be greater than or equal to 0"
        end
      end
    end

    describe "attributes" do
      it "casts original_value as decimal" do
        assert_equal BigDecimal("10000.50"), Consistency.new(original_value: "10000.50", balance: 0).original_value
      end

      it "casts balance as decimal" do
        assert_equal BigDecimal("7000.25"), Consistency.new(original_value: 10_000, balance: "7000.25").balance
      end
    end
  end
end
