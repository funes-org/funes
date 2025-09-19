module Funes
  module MaterializationManagement
    def materialization_model
      @materialization_model ||= nil
    end

    def persistable?
      materialization_model.present? && @materialization_model <= ActiveRecord::Base
    end

    def set_materialization_model(active_record_or_model)
      @materialization_model = active_record_or_model
    end

    def persist_based_on!(state)
      @materialization_model.upsert(state, unique_by: :idx)
    end

    private
      def materialized_instance_based_on(state)
        @materialization_model.new(state)
      end

      def valid_attributes_on(state)
        materialization_model_attributes = @materialization_model.attribute_names.map(&:to_sym)
        state.slice(*materialization_model_attributes)
      end
  end
end
