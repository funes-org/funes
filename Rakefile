require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

# Safeguard against releasing from a fork. `rake release` (bundler/gem_tasks)
# pushes the tag and commits to the remote tracked by the current branch
# (falling back to "origin"). This guard inspects that same remote and aborts
# before any push if it does not point at the canonical funes-org/funes repo.
CANONICAL_RELEASE_REPO = %r{[:/]funes-org/funes(\.git)?\z}

task "release:guard_canonical_remote" do
  branch = `git rev-parse --abbrev-ref HEAD`.strip
  remote = `git config --get branch.#{branch}.remote`.strip
  remote = "origin" if remote.empty?
  url = `git config --get remote.#{remote}.url`.strip

  unless url.match?(CANONICAL_RELEASE_REPO)
    abort <<~MSG
      Refusing to release: the '#{remote}' remote is #{url.inspect}, which is
      not funes-org/funes. Releases must be cut from the canonical repository,
      not a fork. Check out the canonical repo (or fix the remote) and retry.
    MSG
  end
end

Rake::Task["release:source_control_push"].enhance([ "release:guard_canonical_remote" ])

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
