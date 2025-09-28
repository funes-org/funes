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
  end

  class EventStream
    extend ProjectionsManagement

    def append!(new_event)
      return new_event unless new_event.valid?

      if compute_projection_with_new_event(self.class.consistency_projection, new_event).valid?
        @instance_new_events << new_event.persist!(@idx, incremented_version)
      else
        return new_event
      end
      # TODO esboçar como fazer a operação atômica para as "projeções transacionais" que eu espero nesse ponto
      self.class.transactional_projections.each do |projection_class|
        Funes::PersistProjectionJob.perform_now(@idx, projection_class)
      end
      new_event
    end

    # TODO this should be moved to the projection:
    # SomeProjection.process(SomeEventStream.with_id('foo').events + [new_event]) - can be wroth to
    # have a helper to concat events to a given event stream
    def expeculative_append(new_event, projection)
      return new_event unless new_event.valid?

      compute_projection_with_new_event(projection, new_event)
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
      def previous_events
        @previous_events ||= Funes::EventEntry
                               .where(idx:  @idx, created_at: [ ..@as_of ])
                               .order(:created_at)
      end

      def incremented_version
        (@instance_new_events.last&.version || previous_events.last&.version || 0) + 1
      end

      def compute_projection_with_new_event(projection_class, new_event)
        materialization = projection_class.process_events(events + [ new_event ])

        unless materialization.valid?
          materialization.errors.each do |err|
            new_event.errors.add(:base, "#{err.type.to_sym}_on_consistency_projection_#{err.type}".to_sym, **err.options)
          end
        end

        materialization
      end
  end
end
