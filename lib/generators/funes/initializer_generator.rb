require "rails/generators/base"

module Funes
  module Generators
    class InitializerGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)
      desc "Creates a Funes initializer file at config/initializers/funes.rb"

      def create_initializer_file
        template("initializer.rb.tt", "config/initializers/funes.rb")
      end
    end
  end
end
