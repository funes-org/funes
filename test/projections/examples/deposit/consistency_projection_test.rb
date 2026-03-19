require "test_helper"
require "minitest/spec"

module Examples::Deposit
  class ConsistencyProjectionTest < ActiveSupport::TestCase
    extend Minitest::Spec::DSL
    include Funes::ProjectionTestHelper

    describe "event interpretations" do
      describe "DepositEvents::Created handling" do
        it "sets proper values to materialization model's attributes" do
          interpretation = interpret_event_based_on(Examples::Deposit::ConsistencyProjection,
                                                    Examples::DepositEvents::Created.new(effective_date: Time.current,
                                                                                         value: 10_000),
                                                    Examples::Deposit::Consistency.new)

          assert_equal 10_000, interpretation.original_value
          assert_equal 10_000, interpretation.balance
        end
      end

      describe "DepositEvents::Withdrawn handling" do
        it "handles properly the materialization's model balance" do
          assert_equal 7_000,
                       interpret_event_based_on(Examples::Deposit::ConsistencyProjection,
                                                Examples::DepositEvents::Withdrawn.new(effective_date: Time.current,
                                                                                       amount: 3_000),
                                                Examples::Deposit::Consistency.new(balance: 10_000)).balance
        end
      end
    end
  end
end
