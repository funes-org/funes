require "bundler/setup"

APP_RAKEFILE = File.expand_path("test/dummy/Rakefile", __dir__)
load "rails/tasks/engine.rake"

load "rails/tasks/statistics.rake"

require "bundler/gem_tasks"

namespace :docs do
  desc "Generate YARD documentation for current version"
  task :generate do
    require_relative "lib/funes/version"
    version = Funes::VERSION
    output_dir = "docs/v#{version}"

    puts "Generating documentation for version #{version}..."
    system("yard doc --output-dir #{output_dir}") || abort("Failed to generate documentation")

    # Disable AJAX navigation in app.js to fix menu issues with versioned URLs
    app_js_path = "#{output_dir}/js/app.js"
    if File.exist?(app_js_path)
      content = File.read(app_js_path)

      # Find and disable the navigate message handler
      # This forces the menu to use plain HTML links instead of AJAX
      if content =~ /window\.addEventListener\(\s*["']message["']/
        # Simply prevent the fetch by checking for the navigate action and returning early
        content = content.gsub(
          /(if \(e\.data\.action === ["']navigate["']\) \{)/,
          'if (e.data.action === "navigate") { return; // Disabled for versioned URL compatibility'
        )
        File.write(app_js_path, content)
        puts "Disabled AJAX navigation in app.js for reliable menu links"
      end
    end

    # Copy assets to root docs directory
    FileUtils.mkdir_p("docs")
    %w[css js].each do |asset_dir|
      if Dir.exist?("#{output_dir}/#{asset_dir}")
        FileUtils.cp_r("#{output_dir}/#{asset_dir}", "docs/#{asset_dir}")
      end
    end

    puts "Documentation generated in #{output_dir}/"
    Rake::Task["docs:build_index"].invoke
  end

  desc "Build version selector index page"
  task :build_index do
    require "erb"

    versions = Dir.glob("docs/v*").map { |d| File.basename(d) }.sort.reverse

    if versions.empty?
      puts "No versions found. Run 'rake docs:generate' first."
      exit 1
    end

    latest_version = versions.first
    template_path = File.expand_path("lib/templates/docs_index.html.erb", __dir__)
    template = ERB.new(File.read(template_path))
    html = template.result(binding)

    File.write("docs/index.html", html)
    puts "Version index page created at docs/index.html"

    # Create CNAME file for GitHub Pages custom domain
    File.write("docs/CNAME", "docs.funes.org\n")
    puts "CNAME file created for docs.funes.org"

    # Create .nojekyll file to bypass Jekyll processing
    # This is required for YARD's _index.html file to work properly
    File.write("docs/.nojekyll", "")
    puts ".nojekyll file created to bypass Jekyll processing"
  end

  desc "List all documented versions"
  task :list do
    versions = Dir.glob("docs/v*").map { |d| File.basename(d) }.sort.reverse

    if versions.empty?
      puts "No versions documented yet."
    else
      puts "Documented versions:"
      versions.each { |v| puts "  - #{v}" }
    end
  end
end
