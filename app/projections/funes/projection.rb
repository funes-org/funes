require "funes/unknown_event"
require "funes/unknown_materialization_model"
require "funes/invalid_per_change_materialization_table"

module Funes
  # Projections perform the necessary pattern-matching to compute and aggregate the interpretations that the system
  # gives to a particular collection of events. A projection consists of a series of interpretations defined by the
  # programmer and an aggregated representation of these interpretations (therefore, a representation of transient
  # and final states) which is referenced as the *materialized representation*.
  #
  # A projection can be *virtual* or *persistent*. In practical terms, what defines this characteristic is the type
  # of *materialized representation* configured in the projection.
  #
  # - **Virtual projection:** has an ActiveModel instance as its materialized representation. An instance like this
  # is not persistent, but can be calculated at runtime and has characteristics like validation that are quite
  # valuable in the context of a projection.
  #
  # - **Persistent projection:** has an ActiveRecord instance as its materialized representation. A persistent
  # projection has the same validation capabilities but can be persisted and serve the search patterns needed for
  # the application (read model or even [eager read derivation](https://martinfowler.com/bliki/EagerReadDerivation.html)).
  #
  # ## Per-change persistence
  #
  # A persistent projection can opt into keeping a row per *version* of its state (per-change persistence) via
  # {persists_per_change}. The row's key is `(idx, version)`; version values are stringified event positions (`"1"`,
  # `"2"`, …) plus the sentinel `"final"` when a `final_state` block is defined.
  #
  # @see persists_per_change
  #
  # ## Bitemporal Queries
  #
  # Projections support two temporal dimensions:
  #
  # - **Record history** (`as_of`): Determines which events are loaded from the database (by `created_at`).
  #   This is handled at the EventStream level before events reach the projection.
  # - **Actual history** (`at`): The temporal reference for the projection. Passed to all
  #   interpretation blocks as the third argument.
  #
  # All interpretation blocks (`initial_state`, `interpretation_for`, and `final_state`) receive `at`
  # as their temporal reference, representing when events actually occurred rather than when the system
  # recorded them.
  class Projection
    class << self
      # Registers an interpretation block for a given event type.
      #
      # Inside interpretation blocks, you can reject events by calling +event.errors.add(...)+ on the
      # event. When used as a **consistency projection**, these errors will be transferred to
      # +event.interpretation_errors+ and the event will not be persisted. In transactional or async
      # projections, errors added to the event have no rejection effect and will be logged as a warning.
      #
      # @param [Class<Funes::Event>] event_type The event class constant that will be interpreted.
      # @yield [state, event, at] Block invoked with the current state, the event and the temporal reference.
      #   It should return a new version of the transient state.
      # @yieldparam [ActiveModel::Model, ActiveRecord::Base] transient_state The current transient state
      # @yieldparam [Funes::Event] event Event instance.
      # @yieldparam [Time] at The temporal reference point for the projection.
      # @yieldreturn [ActiveModel::Model, ActiveRecord::Base] the new transient state
      # @return [void]
      #
      # @example Rejecting an event in a consistency projection
      #   class YourProjection < Funes::Projection
      #     interpretation_for Order::Placed do |transient_state, current_event, _at|
      #       current_event.errors.add(:base, "Order total too high") if current_event.amount > 10_000
      #       transient_state.assign_attributes(total: (transient_state.total || 0) + current_event.amount)
      #       transient_state
      #     end
      #   end
      def interpretation_for(event_type, &block)
        @interpretations ||= {}
        @interpretations[event_type] = block
      end

      # Registers the initial transient state that will be used for the current projection's interpretations.
      #
      # *Default behavior:* When no block is provided the initial state defaults to a new instance of
      # the configured materialization model.
      #
      # @yield [materialization_model, at] Block invoked to produce the initial state.
      # @yieldparam [Class<ActiveRecord::Base>, Class<ActiveModel::Model>] materialization_model The materialization model constant.
      # @yieldparam [Time] at The temporal reference point for the projection.
      # @yieldreturn [ActiveModel::Model, ActiveRecord::Base] the new transient state
      # @return [void]
      #
      # @example
      #   class YourProjection < Funes::Projection
      #     initial_state do |materialization_model, _at|
      #       materialization_model.new(some: :specific, value: 42)
      #     end
      #   end
      def initial_state(&block)
        @interpretations ||= {}
        @interpretations[:init] = block
      end

      # Register a final interpretation of the state.
      #
      # *Default behavior:* when this is not defined the projection does nothing after the interpretations
      #
      # When the projection is configured with {persists_per_change}, declaring a `final_state` block also
      # causes a row with `version = "final"` to be written alongside the per-event-position rows.
      #
      # @yield [transient_state, at] Block invoked to produce the final state.
      # @yieldparam [ActiveModel::Model, ActiveRecord::Base] transient_state The current transient state after all interpretations.
      # @yieldparam [Time] at The temporal reference point for the projection.
      # @yieldreturn [ActiveModel::Model, ActiveRecord::Base] the final transient state instance
      # @return [void]
      #
      # @example
      #   class YourProjection < Funes::Projection
      #     final_state do |transient_state, _at|
      #       # TODO...
      #     end
      #   end
      def final_state(&block)
        @interpretations ||= {}
        @interpretations[:final] = block
      end

      # Register the projection's materialization model
      #
      # @param [Class<ActiveRecord::Base>, Class<ActiveModel::Model>] active_record_or_model The materialization model class.
      # @return [void]
      #
      # @example Virtual projection (non-persistent, ActiveModel)
      #   class YourProjection < Funes::Projection
      #     materialization_model YourActiveModelClass
      #   end
      #
      # @example Persistent projection (persisted read model, ActiveRecord)
      #   class YourProjection < Funes::Projection
      #     materialization_model YourActiveRecordClass
      #   end
      def materialization_model(active_record_or_model)
        @materialization_model = active_record_or_model
      end

      # It changes the sensibility of the projection about events that it doesn't know how to interpret
      #
      # By default, a projection ignores events that it doesn't have interpretations for. This method informs the
      # projection that in cases like that an Funes::UnknownEvent should be raised and the DB transaction should be
      # rolled back.
      #
      # @return [void]
      #
      # @example
      #   class YourProjection < Funes::Projection
      #     raise_on_unknown_events
      #   end
      def raise_on_unknown_events
        @throws_on_unknown_events = true
      end

      # Opts this projection into per-change persistence: one row per version of the projection state
      # instead of a single row per `idx`.
      #
      # When enabled, {materialize!} computes the full sequence of state versions in memory and, within a
      # single database transaction, deletes any existing rows for the `idx` and writes the new set via
      # `UPSERT`. The table referenced by {materialization_model} must be an ActiveRecord model whose
      # backing table carries the `version` column and a `(idx, version)` unique key — use
      # {Funes::Generators::PerChangeMaterializationTableGenerator} to create one. If the requirement is
      # not met, {Funes::InvalidPerChangeMaterializationTable} is raised on the first materialization.
      #
      # Row versions:
      # - The **position** of each event (1-indexed) that has a matching interpretation is stringified
      #   and used as its row's `version`. Events without a matching interpretation produce no row.
      # - If `final_state` is declared, one additional row is written with `version = "final"`.
      #
      # Regular persistent projections are unaffected by this flag.
      #
      # @return [void]
      #
      # @example
      #   class BalanceHistoryProjection < Funes::Projection
      #     materialization_model BalanceHistory
      #     persists_per_change
      #
      #     interpretation_for Deposit::Created   do |state, e, _at| state.assign_attributes(balance: e.value); state end
      #     interpretation_for Deposit::Withdrawn do |state, e, _at| state.assign_attributes(balance: state.balance - e.amount); state end
      #   end
      def persists_per_change
        @persists_per_change = true
      end

      # @!visibility private
      def process_events(events_collection, at: nil, consistency: false)
        new(self.instance_variable_get(:@interpretations),
            self.instance_variable_get(:@materialization_model),
            self.instance_variable_get(:@throws_on_unknown_events),
            self.instance_variable_get(:@persists_per_change))
          .process_events(events_collection, at: at, consistency: consistency)
      end

      # @!visibility private
      def materialize!(events_collection, idx, at: nil)
        new(self.instance_variable_get(:@interpretations),
            self.instance_variable_get(:@materialization_model),
            self.instance_variable_get(:@throws_on_unknown_events),
            self.instance_variable_get(:@persists_per_change))
          .materialize!(events_collection, idx, at: at)
      end
    end

    # @!visibility private
    def initialize(interpretations, materialization_model, throws_on_unknown_events, persists_per_change = false)
      @interpretations = interpretations
      @materialization_model = materialization_model
      raise Funes::UnknownMaterializationModel,
            "There is no materialization model configured on #{self.class.name}" unless @materialization_model.present?


      @throws_on_unknown_events = throws_on_unknown_events
      @persists_per_change = persists_per_change
    end

    # @!visibility private
    def process_events(events_collection, at: nil, consistency: false)
      _pairs, state = compute_versioned_states(events_collection, at: at, consistency: consistency)
      state
    end

    # @!visibility private
    def materialize!(events_collection, idx, at: nil)
      pairs, state = compute_versioned_states(events_collection, at: at)
      materialized_model_instance = materialized_model_instance_based_on(state)

      if persists_per_change?
        unless materialization_model_is_persistable?
          raise Funes::InvalidPerChangeMaterializationTable,
                "`persists_per_change` requires an ActiveRecord materialization model; " \
                "#{@materialization_model.name} is not persistable."
        end
        persist_versioned_states!(idx, pairs)
      elsif materialization_model_is_persistable?
        state.assign_attributes(idx:)
        persist_based_on!(state)
      end

      materialized_model_instance
    end

    private
      def throws_on_unknown_events?
        @throws_on_unknown_events || false
      end

      def persists_per_change?
        @persists_per_change || false
      end

      def interpretations
        @interpretations || {}
      end

      def materialized_model_instance_based_on(state)
        @materialization_model.new(state.attributes)
      end

      def materialization_model_is_persistable?
        @materialization_model.present? && @materialization_model <= ActiveRecord::Base
      end

      def persist_based_on!(state)
        raise ActiveRecord::RecordInvalid.new(state) unless state.valid?
        @materialization_model.upsert(state.attributes, unique_by: :idx)
      end

      def compute_versioned_states(events_collection, at: nil, consistency: false)
        actual_at = at || Time.current
        state = interpretations[:init].present? \
                  ? interpretations[:init].call(@materialization_model, actual_at) \
                  : @materialization_model.new

        pairs = []
        events_collection.each_with_index do |event, index|
          fn = @interpretations[event.class]
          if fn.nil? && throws_on_unknown_events?
            raise Funes::UnknownEvent, "Events of the type #{event.class} are not processable"
          end

          if fn
            event_at = event.persisted? ? event.occurred_at : actual_at
            state = fn.call(state, event, event_at)
            pairs << [ (index + 1).to_s, snapshot_state(state) ]
          end

          warn_about_ineffective_errors(event) unless consistency
        end

        if interpretations[:final].present?
          state = interpretations[:final].call(state, actual_at)
          pairs << [ "final", snapshot_state(state) ]
        end

        [ pairs, state ]
      end

      def snapshot_state(state)
        @materialization_model.new(state.attributes)
      end

      def persist_versioned_states!(idx, pairs)
        unless @materialization_model.column_names.include?("version")
          raise Funes::InvalidPerChangeMaterializationTable,
                "`persists_per_change` requires the materialization model's table to have a `version` column. " \
                "Generate one with `bin/rails generate funes:per_change_materialization_table #{@materialization_model.name}`."
        end

        @materialization_model.transaction do
          @materialization_model.where(idx: idx).delete_all
          pairs.each do |version, snapshot|
            snapshot.assign_attributes(idx: idx, version: version)
            raise ActiveRecord::RecordInvalid.new(snapshot) unless snapshot.valid?
            @materialization_model.upsert(snapshot.attributes, unique_by: [ :idx, :version ])
          end
        end
      end

      def warn_about_ineffective_errors(event)
        return unless event.is_a?(Funes::Event)

        base_errors = event.send(:base_errors)
        return if base_errors.empty?

        Rails.logger.warn("[Funes] Errors added to #{event.class} in a non-consistency projection " \
                          "have no effect and will be discarded: #{base_errors.full_messages.join(', ')}")
      end
  end
end
