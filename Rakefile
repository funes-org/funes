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

    # Create CNAME file for GitHub Pages custom domain
    File.write("docs/CNAME", "docs.funes.org\n")
    puts "CNAME file created for docs.funes.org"

    # Create .nojekyll file to bypass Jekyll processing
    # This is required for YARD's _index.html file to work properly
    File.write("docs/.nojekyll", "")
    puts ".nojekyll file created to bypass Jekyll processing"

    puts "Documentation generated in #{output_dir}/"
  end
end
