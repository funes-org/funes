module Funes
  module ProjectionsManagement
    def consistency_projection
      @consistency_projection ||= nil
    end

    def set_consistency_projection(projection)
      @consistency_projection = projection
    end

    def transactional_projections
      @transactional_projections ||= []
    end

    def set_transactional_projection(projection)
      transactional_projections << projection
    end

    def async_projections
      @async_projections ||= []
    end

    def add_async_projection(projection, **options)
      async_projections << { class: projection, options: }
    end
  end

  class EventStream
    extend ProjectionsManagement

    def append!(new_event)
      return new_event unless new_event.valid?

      # TODO: a projeção de consistência não deveria ser obrigatória

      if compute_projection_with_new_event(self.class.consistency_projection, new_event).valid?
        begin
          @instance_new_events << new_event.persist!(@idx, incremented_version)
        rescue ActiveRecord::RecordNotUnique
          new_event.errors.add(:base, I18n.t("funes.events.racing_condition_on_insert"))
        end
      else
        return new_event
      end
      run_transactional_projections
      schedule_async_projections

      new_event
    end

    def initialize(entity_id, as_of = nil)
      @idx = entity_id
      @instance_new_events = []
      @as_of = as_of ? as_of : Time.current
    end

    def self.with_id(idx)
      new(idx)
    end

    def events
      (previous_events + @instance_new_events).map(&:to_klass_instance)
    end

    private
      def run_transactional_projections
        self.class.transactional_projections.each do |projection_class|
          Funes::PersistProjectionJob.perform_now(@idx, projection_class)
        end
      end

      def schedule_async_projections
        self.class.async_projections.each do |projection|
          Funes::PersistProjectionJob.set(projection[:options]).perform_later(@idx, projection[:class])
        end
      end

      def previous_events
        @previous_events ||= Funes::EventEntry
                               .where(idx: @idx, created_at: [ ..@as_of ])
                               .order(:created_at)
      end

      def incremented_version
        (@instance_new_events.last&.version || previous_events.last&.version || 0) + 1
      end

      def compute_projection_with_new_event(projection_class, new_event)
        materialization = projection_class.process_events(events + [ new_event ])
        unless materialization.valid?
          new_event.event_errors = new_event.errors
          new_event.adjacent_state_errors = materialization.errors
        end

        materialization
      end
  end
end
