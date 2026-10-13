require "test_helper"
require "minitest/spec"

class IdempotencyKeyTest < ActiveSupport::TestCase
  extend Minitest::Spec::DSL
  include ActiveJob::TestHelper

  class WithdrawKeyedEventStream < Funes::EventStream
    consistency_projection Examples::Deposit::ConsistencyProjection
    actual_time_attribute :effective_date

    add_transactional_projection Examples::Deposit::SnapshotProjection
    add_async_projection Examples::Deposit::LastActivityProjection

    requires_idempotency_key_for Examples::DepositEvents::Withdrawn
  end

  class ArrayKeyedEventStream < Funes::EventStream
    requires_idempotency_key_for [ Examples::DepositEvents::Created, Examples::DepositEvents::Withdrawn ]
  end

  class FullyKeyedEventStream < Funes::EventStream
    requires_idempotency_key
  end

  # Simulates a concurrent append that commits between the fast-path lookup and the insert:
  # the first lookup misses, so the insert hits the unique index.
  class RacingEventStream < WithdrawKeyedEventStream
    private
      def entry_with_idempotency_key(idempotency_key)
        @lookups = @lookups.to_i + 1
        @lookups == 1 ? nil : super
      end
  end

  let(:idx) { "idempotency-#{SecureRandom.uuid}" }
  let(:other_idx) { "idempotency-other-#{SecureRandom.uuid}" }
  let(:today) { Date.today }
  let(:stream) { WithdrawKeyedEventStream.for(idx) }

  def created(value: 100)
    Examples::DepositEvents::Created.new(value: value, effective_date: today)
  end

  def withdrawn(amount: 30)
    Examples::DepositEvents::Withdrawn.new(amount: amount, effective_date: today)
  end

  describe "a stream with no idempotency key declaration" do
    it "appends without a key and stores NULL" do
      event = Examples::DepositEventStream.for(idx).append!(created)

      assert_nil event.idempotency_key
      assert_nil Funes::EventEntry.find_by(idx: idx).idempotency_key
      refute event.duplicate?
    end

    it "accepts and enforces a key given at the call site" do
      original = Examples::DepositEventStream.for(idx).append!(created, idempotency_key: "creation:1")
      repeated = nil

      assert_no_difference -> { Funes::EventEntry.count } do
        repeated = Examples::DepositEventStream.for(idx).append!(created, idempotency_key: "creation:1")
      end

      assert_equal "creation:1", original.idempotency_key
      assert repeated.duplicate?
    end

    it "never collides events appended without a key" do
      event_stream = Examples::DepositEventStream.for(idx)
      event_stream.append!(created)

      assert_difference -> { Funes::EventEntry.where(idx: idx).count }, 2 do
        event_stream.append!(withdrawn(amount: 10))
        event_stream.append!(withdrawn(amount: 10))
      end
    end
  end

  describe "requires_idempotency_key_for" do
    it "appends event types outside the list without a key" do
      event = stream.append!(created)

      assert event.persisted?
      assert_nil event.idempotency_key
    end

    it "raises MissingIdempotencyKeyError in append! for a listed event type without a key" do
      stream.append!(created)

      assert_no_difference -> { Funes::EventEntry.count } do
        assert_raises(Funes::MissingIdempotencyKeyError) { stream.append!(withdrawn) }
      end
    end

    it "raises MissingIdempotencyKeyError in the non-bang append too" do
      stream.append!(created)

      assert_raises(Funes::MissingIdempotencyKeyError) { stream.append(withdrawn) }
    end

    it "treats a blank key as missing" do
      stream.append!(created)

      assert_raises(Funes::MissingIdempotencyKeyError) { stream.append!(withdrawn, idempotency_key: "") }
    end

    it "persists the key given at the call site and exposes it on the event" do
      stream.append!(created)
      event = stream.append!(withdrawn, idempotency_key: "kafka:withdrawals:3:88121")

      assert event.persisted?
      refute event.duplicate?
      assert_equal "kafka:withdrawals:3:88121", event.idempotency_key
      assert_equal "kafka:withdrawals:3:88121", WithdrawKeyedEventStream.for(idx).events.last.idempotency_key
      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "accepts the event classes as an array" do
      assert_raises(Funes::MissingIdempotencyKeyError) { ArrayKeyedEventStream.for(idx).append!(created) }
      assert_raises(Funes::MissingIdempotencyKeyError) { ArrayKeyedEventStream.for(idx).append!(withdrawn) }
    end
  end

  describe "requires_idempotency_key" do
    it "raises MissingIdempotencyKeyError for any event type, in append and append!" do
      ledger = FullyKeyedEventStream.for(idx)

      assert_raises(Funes::MissingIdempotencyKeyError) { ledger.append!(created) }
      assert_raises(Funes::MissingIdempotencyKeyError) { ledger.append(withdrawn) }
      refute Funes::EventEntry.exists?(idx: idx)
    end

    it "accepts every event type given a key" do
      ledger = FullyKeyedEventStream.for(idx)

      assert_difference -> { Funes::EventEntry.where(idx: idx).count }, 2 do
        ledger.append!(created, idempotency_key: "kafka:ledger:0:1")
        ledger.append!(withdrawn, idempotency_key: "kafka:ledger:0:2")
      end
    end
  end

  describe "a repeated key with the same event class and attributes" do
    before do
      stream.append!(created)
      @original = stream.append!(withdrawn, idempotency_key: "charge:ch_1")
      clear_enqueued_jobs
    end

    it "writes nothing and returns the given event carrying the original entry" do
      redelivery = withdrawn
      returned = nil

      assert_no_difference -> { Funes::EventEntry.count } do
        returned = WithdrawKeyedEventStream.for(idx).append!(redelivery, idempotency_key: "charge:ch_1")
      end

      assert_same redelivery, returned
      assert returned.duplicate?
      assert returned.persisted?
      assert returned.errors.empty?
      assert_equal 2, returned.version
      assert_equal @original.created_at, returned.created_at
      assert_equal "charge:ch_1", returned.idempotency_key
    end

    it "does the same with the non-bang append" do
      returned = WithdrawKeyedEventStream.for(idx).append(withdrawn, idempotency_key: "charge:ch_1")

      assert returned.duplicate?
      assert_equal 2, returned.version
    end

    it "does not run projections again" do
      assert_no_enqueued_jobs do
        WithdrawKeyedEventStream.for(idx).append!(withdrawn, idempotency_key: "charge:ch_1")
      end

      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "is a duplicate even when the consistency projection would now reject the event" do
      big = Examples::DepositEvents::Withdrawn.new(amount: 70, effective_date: today)
      stream.append!(big, idempotency_key: "charge:ch_2")

      repeated = WithdrawKeyedEventStream.for(idx).append!(
        Examples::DepositEvents::Withdrawn.new(amount: 70, effective_date: today), idempotency_key: "charge:ch_2"
      )

      assert repeated.duplicate?
      assert_equal 0, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "does not mark the original event as a duplicate" do
      refute @original.duplicate?
    end

    it "does not show up twice in the events of the stream instance that received the repeat" do
      repeating_stream = WithdrawKeyedEventStream.for(idx)
      repeating_stream.append!(withdrawn, idempotency_key: "charge:ch_1")

      assert_equal 2, repeating_stream.events.size
    end
  end

  describe "a repeated key recorded with different metainformation" do
    before do
      Funes.configure { |c| c.event_metainformation_attributes = [ :user_id ] }
      Funes::EventMetainformation.setup_attributes!
    end

    after do
      Funes::EventMetainformation.reset
      Funes::EventMetainformation.clear_validators!
      Funes.instance_variable_set(:@configuration, Funes::Configuration.new)
    end

    it "is a duplicate, and the original metainformation is kept" do
      stream.append!(created)
      Funes::EventMetainformation.user_id = 1
      stream.append!(withdrawn, idempotency_key: "charge:ch_1")

      Funes::EventMetainformation.user_id = 2
      repeated = nil
      assert_no_difference -> { Funes::EventEntry.count } do
        repeated = WithdrawKeyedEventStream.for(idx).append!(withdrawn, idempotency_key: "charge:ch_1")
      end

      assert repeated.duplicate?
      assert_equal({ "user_id" => 1 }, Funes::EventEntry.find_by(idx: idx, idempotency_key: "charge:ch_1").meta_info)
      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end
  end

  describe "a repeated key with a different event class or attributes" do
    before do
      stream.append!(created)
      stream.append!(withdrawn, idempotency_key: "charge:ch_1")
      clear_enqueued_jobs
    end

    it "raises IdempotencyKeyConflictError in append! and writes nothing" do
      conflicting = withdrawn(amount: 50)

      assert_no_enqueued_jobs do
        assert_no_difference -> { Funes::EventEntry.count } do
          assert_raises(Funes::IdempotencyKeyConflictError) do
            WithdrawKeyedEventStream.for(idx).append!(conflicting, idempotency_key: "charge:ch_1")
          end
        end
      end

      refute conflicting.persisted?
      refute conflicting.duplicate?
      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "adds an error and leaves the event unpersisted in the non-bang append" do
      conflicting = withdrawn(amount: 50)

      assert_no_enqueued_jobs do
        assert_no_difference -> { Funes::EventEntry.count } do
          WithdrawKeyedEventStream.for(idx).append(conflicting, idempotency_key: "charge:ch_1")
        end
      end

      refute conflicting.persisted?
      refute conflicting.duplicate?
      assert_equal [ I18n.t("funes.events.idempotency_key_conflict") ], conflicting.errors[:base]
      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "is a conflict when only the event class differs" do
      assert_raises(Funes::IdempotencyKeyConflictError) do
        WithdrawKeyedEventStream.for(idx).append!(created, idempotency_key: "charge:ch_1")
      end
    end

    it "rolls back sibling writes inside a host-managed transaction" do
      sibling_idx = "sibling-#{SecureRandom.uuid}"

      assert_raises(Funes::IdempotencyKeyConflictError) do
        ActiveRecord::Base.transaction do
          Examples::Deposit::Snapshot.create!(idx: sibling_idx, created_at: today, original_value: 10, balance: 10)
          WithdrawKeyedEventStream.for(idx).append!(withdrawn(amount: 50), idempotency_key: "charge:ch_1")
        end
      end

      refute Examples::Deposit::Snapshot.exists?(sibling_idx)
    end
  end

  describe "the same key on another stream" do
    let(:other_stream) { WithdrawKeyedEventStream.for(other_idx) }

    before do
      stream.append!(created)
      other_stream.append!(created)
      @original = stream.append!(withdrawn, idempotency_key: "fee:2026-02")
      clear_enqueued_jobs
    end

    it "raises IdempotencyKeyUsedInAnotherStreamError in append!, naming the stream that holds the key" do
      event = withdrawn
      error = nil

      assert_no_enqueued_jobs do
        assert_no_difference -> { Funes::EventEntry.count } do
          error = assert_raises(Funes::IdempotencyKeyUsedInAnotherStreamError) do
            other_stream.append!(event, idempotency_key: "fee:2026-02")
          end
        end
      end

      assert_kind_of Funes::IdempotencyKeyConflictError, error
      assert_equal idx, error.idx
      assert_equal "fee:2026-02", error.idempotency_key
      assert_equal Examples::DepositEvents::Withdrawn.name, error.klass
      assert_equal @original.version, error.version
      refute event.persisted?
      refute event.duplicate?
      assert_equal 100, Examples::Deposit::Snapshot.find(other_idx).balance
    end

    it "adds an error naming that stream and leaves the event unpersisted in the non-bang append" do
      event = withdrawn

      assert_no_difference -> { Funes::EventEntry.count } do
        other_stream.append(event, idempotency_key: "fee:2026-02")
      end

      refute event.persisted?
      refute event.duplicate?
      assert_equal [ I18n.t("funes.events.idempotency_key_used_in_another_stream", idx: idx) ],
                   event.errors[:base]
      assert_equal 100, Examples::Deposit::Snapshot.find(other_idx).balance
    end

    it "does not compare the payload: a different event with the key is the same error" do
      error = assert_raises(Funes::IdempotencyKeyUsedInAnotherStreamError) do
        other_stream.append!(created, idempotency_key: "fee:2026-02")
      end

      assert_equal idx, error.idx
    end

    it "accepts the key once it carries the entity" do
      event = other_stream.append!(withdrawn, idempotency_key: "fee:#{other_idx}:2026-02")

      assert event.persisted?
      refute event.duplicate?
      assert_equal 70, Examples::Deposit::Snapshot.find(other_idx).balance
    end
  end

  describe "a redelivered creation message, each delivery with a freshly minted idx" do
    let(:message_key) { "kafka:deposits:0:4411" }

    before do
      @first_idx = SecureRandom.uuid
      WithdrawKeyedEventStream.for(@first_idx).append!(created, idempotency_key: message_key)
      clear_enqueued_jobs
    end

    it "creates no second stream and tells the consumer where the first delivery landed" do
      error = nil

      assert_no_enqueued_jobs do
        assert_no_difference -> { Funes::EventEntry.count } do
          error = assert_raises(Funes::IdempotencyKeyUsedInAnotherStreamError) do
            WithdrawKeyedEventStream.for(SecureRandom.uuid).append!(created, idempotency_key: message_key)
          end
        end
      end

      assert_equal @first_idx, error.idx
      assert_equal 1, Examples::Deposit::Snapshot.count
    end
  end

  describe "the database index" do
    let(:index) { Funes::EventEntry.connection.indexes(:event_entries).find { |i| i.columns == [ "idempotency_key" ] } }

    it "is unique and partial, so events without a key add nothing to it" do
      assert index.unique
      assert_match(/idempotency_key IS NOT NULL/i, index.where)
    end

    it "serves the lookup the append performs by key" do
      plan = Funes::EventEntry.where(idempotency_key: "charge:ch_1").explain.inspect

      assert_match(/USING (COVERING )?INDEX #{index.name}/, plan)
    end

    it "rejects a second entry with the same key on any stream regardless of application checks" do
      attributes = { klass: Examples::DepositEvents::Withdrawn.name, props: { amount: 1 }, version: 1,
                     created_at: Time.current, occurred_at: Time.current, idempotency_key: "charge:ch_1" }
      Funes::EventEntry.create!(attributes.merge(idx: idx))

      assert_raises(ActiveRecord::RecordNotUnique) do
        ActiveRecord::Base.transaction(requires_new: true) do
          Funes::EventEntry.create!(attributes.merge(idx: other_idx))
        end
      end
    end
  end

  describe "when a concurrent append with the same key wins the race for the insert" do
    before do
      stream.append!(created)
      stream.append!(withdrawn, idempotency_key: "charge:ch_1")
      clear_enqueued_jobs
    end

    it "resolves to a duplicate when class and attributes match" do
      racing = withdrawn
      returned = nil

      assert_no_enqueued_jobs do
        assert_no_difference -> { Funes::EventEntry.count } do
          returned = RacingEventStream.for(idx).append!(racing, idempotency_key: "charge:ch_1")
        end
      end

      assert_same racing, returned
      assert returned.duplicate?
      assert returned.errors.empty?
      assert_equal 2, returned.version
      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "resolves to a duplicate in the non-bang append" do
      returned = RacingEventStream.for(idx).append(withdrawn, idempotency_key: "charge:ch_1")

      assert returned.duplicate?
      assert returned.errors.empty?
    end

    it "raises IdempotencyKeyConflictError in append! when the attributes differ" do
      racing = withdrawn(amount: 50)

      assert_no_difference -> { Funes::EventEntry.count } do
        assert_raises(Funes::IdempotencyKeyConflictError) do
          RacingEventStream.for(idx).append!(racing, idempotency_key: "charge:ch_1")
        end
      end

      refute racing.persisted?
      assert_equal 70, Examples::Deposit::Snapshot.find(idx).balance
    end

    it "adds the conflict error in the non-bang append when the attributes differ" do
      racing = withdrawn(amount: 50)

      RacingEventStream.for(idx).append(racing, idempotency_key: "charge:ch_1")

      refute racing.persisted?
      assert_equal [ I18n.t("funes.events.idempotency_key_conflict") ], racing.errors[:base]
    end

    it "raises IdempotencyKeyUsedInAnotherStreamError when the winner was on another stream" do
      other_stream = RacingEventStream.for(other_idx)
      other_stream.append!(created)
      racing = withdrawn

      assert_no_difference -> { Funes::EventEntry.count } do
        error = assert_raises(Funes::IdempotencyKeyUsedInAnotherStreamError) do
          other_stream.append!(racing, idempotency_key: "charge:ch_1")
        end
        assert_equal idx, error.idx
      end

      refute racing.persisted?
    end
  end

  describe "when a version conflict races the insert of an event with a new key" do
    before do
      stream.append!(created)
      travel_to(1.minute.from_now) do
        Funes::EventEntry.create!(klass: Examples::DepositEvents::Withdrawn.name, idx: idx, version: 2,
                                  props: { amount: 5, effective_date: today }, occurred_at: Time.current)
      end
    end

    it "keeps the racing-condition error in the non-bang append" do
      event = withdrawn

      stream.append(event, idempotency_key: "charge:ch_9")

      refute event.persisted?
      refute event.duplicate?
      assert_equal [ I18n.t("funes.events.racing_condition_on_insert") ], event.errors[:base]
    end

    it "raises ActiveRecord::RecordInvalid in append!" do
      event = withdrawn

      error = assert_raises(ActiveRecord::RecordInvalid) { stream.append!(event, idempotency_key: "charge:ch_9") }

      assert_same event, error.record
      refute event.persisted?
    end
  end
end
