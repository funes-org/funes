require "test_helper"
require "minitest/spec"

class PersistProjectionJobTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  # @TODO: verify persistence of projection's materialization model
  # Given an EventStream and projection the job needs to process them and persists the proper materialization model

  it { skip "projection's materialization model persistence checks" }
end
