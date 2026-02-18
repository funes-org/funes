module Funes
  class Engine < ::Rails::Engine
    isolate_namespace Funes

    config.before_configuration do
      config.funes = Funes.configuration
    end

    initializer "funes.autoload", before: :set_autoload_paths do |app|
      engine_root = config.root

      %w[models event_streams projections helpers].each do |dir|
        path = engine_root.join("app", dir)
        app.config.autoload_paths << path
        app.config.eager_load_paths << path
      end
    end

    config.after_initialize do
      Funes::EventMetainformation.setup_attributes!

      Funes::Event.filter_attributes = Rails.application.config.filter_parameters
    end
  end
end
