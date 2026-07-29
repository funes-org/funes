require "test_helper"
require "minitest/spec"

module Examples::Deposit
  class ConsistencyProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    projection Examples::Deposit::ConsistencyProjection

    describe "event interpretations" do
      describe "DepositEvents::Created handling" do
        it "sets proper values to materialization model's attributes" do
          result = interpret(Examples::DepositEvents::Created.new(effective_date: Time.current, value: 10_000),
                             given: Examples::Deposit::Consistency.new)

          assert_equal 10_000, result.original_value
          assert_equal 10_000, result.balance
        end

        it "carries the event's customer reference into the materialization model" do
          customer = Examples::Customer.create!(name: "Ada")

          result = interpret(Examples::DepositEvents::Created.new(effective_date: Time.current, value: 10_000,
                                                                  customer: customer),
                             given: Examples::Deposit::Consistency.new)

          assert_equal customer, result.customer
          assert_equal customer.id, result.attributes["customer_id"]
        end
      end

      describe "DepositEvents::Withdrawn handling" do
        it "handles properly the materialization's model balance" do
          result = interpret(Examples::DepositEvents::Withdrawn.new(effective_date: Time.current, amount: 3_000),
                             given: Examples::Deposit::Consistency.new(balance: 10_000))

          assert_equal 7_000, result.balance
        end
      end
    end
  end
end
