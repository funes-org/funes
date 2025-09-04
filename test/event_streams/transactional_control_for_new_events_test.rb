require "test_helper"
require "minitest/spec"

class TransactionalControlForNewEventsTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  # @TODO: transactional control for the act of event appending
  # These tests must cover transaction's commit/rollback properly handling both events' addition to
  # the events store and transactional projections persistence

  it { skip "transactional control" }
end
