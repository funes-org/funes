module Funes
  class Engine < ::Rails::Engine
    isolate_namespace Funes

    initializer "funes.autoload", before: :set_autoload_paths do |app|
      engine_root = config.root
      app.config.autoload_paths << engine_root.join("lib")
    end
  end
end
