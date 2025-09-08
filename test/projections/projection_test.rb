require "test_helper"
require "minitest/spec"

class ProjectionTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL

  describe "function management" do
    it "sets event interpretations properly as Proc objects" do
      assert SimpleProjection.interpretations["Test::Start"].is_a?(Proc)
      assert SimpleProjection.interpretations["Test::Add"].is_a?(Proc)
    end

    it "returns nil instead of a Proc when accessing undefined event interpretations" do
      assert_not SimpleProjection.interpretations["Test::Nonexistent"].is_a?(Proc)
    end
  end

  describe "accumulation of state interpretations through #process_events" do
    it "accumulates state changes correctly when processing a sequence of events" do
      assert_equal 11, SimpleProjection.process_events([ { type: "Test::Start", value: 5 },
                                                        { type: "Test::Add", value: 4 },
                                                        { type: "Test::Add", value: 2 } ])
    end

    it "ignores unknown events while continuing to process valid events in the sequence" do
      assert_equal 7, SimpleProjection.process_events([ { type: "Test::Start", value: 5 },
                                                       { type: "Test::Unknown", value: 4 },
                                                       { type: "Test::Add", value: 2 } ])
    end
  end

  describe "exceptions management while interpreting unknow events" do
    it "silently ignores unknown events by default without raising exceptions" do
      assert_nothing_raised do
        SimpleProjection.process_events([ { type: "Test::Start", value: 5 },
                                         { type: "Test::Unknown", value: 4 } ])
      end
    end

    it "raises an exception when processing unknown events with strict configuration enabled" do
      assert_raises RuntimeError do
        StrictProjection.process_events([ { type: "Test::Start", value: 5 },
                                         { type: "Test::Unknown", value: 4 } ])
      end
    end
  end
end
