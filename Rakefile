require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

namespace :docs do
  desc "Generate YARD documentation"
  task :generate do
    output_dir = "docs"

    puts "Generating documentation..."
    system("yard doc --output-dir #{output_dir}") || abort("Failed to generate documentation")

    puts "Documentation generated in #{output_dir}/"
  end
end

namespace :guides do
  guides_dir = File.expand_path("guides", __dir__)

  desc "Install Jekyll dependencies for guides (one-time setup)"
  task :setup do
    Bundler.with_unbundled_env do
      Dir.chdir(guides_dir) do
        system("bundle install") || abort("Failed to install guides dependencies")
      end
    end
  end

  desc "Build the guides site into guides/_site/"
  task :build do
    Bundler.with_unbundled_env do
      Dir.chdir(guides_dir) do
        system("bundle exec jekyll build") || abort("Failed to build guides")
      end
    end
  end

  desc "Start Jekyll dev server with live reload at localhost:4000/guides/"
  task :serve do
    Bundler.with_unbundled_env do
      Dir.chdir(guides_dir) do
        system("bundle exec jekyll serve --livereload")
      end
    end
  end
end
