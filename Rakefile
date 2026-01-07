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
    versions = Dir.glob("docs/v*").map { |d| File.basename(d) }.sort.reverse

    if versions.empty?
      puts "No versions found. Run 'rake docs:generate' first."
      exit 1
    end

    latest_version = versions.first

    html = <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Funes Documentation</title>
        <link rel="stylesheet" href="css/style.css">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            line-height: 1.6;
          }
          h1 {
            color: #333;
            border-bottom: 2px solid #0066cc;
            padding-bottom: 10px;
          }
          .version-list {
            list-style: none;
            padding: 0;
          }
          .version-list li {
            margin: 10px 0;
            padding: 15px;
            background: #f5f5f5;
            border-radius: 5px;
          }
          .version-list a {
            text-decoration: none;
            color: #0066cc;
            font-size: 18px;
            font-weight: 500;
          }
          .version-list a:hover {
            text-decoration: underline;
          }
          .latest-badge {
            background: #0066cc;
            color: white;
            padding: 3px 8px;
            border-radius: 3px;
            font-size: 12px;
            margin-left: 10px;
          }
          .description {
            color: #666;
            margin-top: 20px;
          }
        </style>
      </head>
      <body>
        <h1>Funes Documentation</h1>
        <p class="description">Event Sourcing for Rails - Select a version to view documentation</p>

        <ul class="version-list">
    HTML

    versions.each do |version|
      is_latest = version == latest_version
      badge = is_latest ? '<span class="latest-badge">latest</span>' : ''
      html += "      <li><a href=\"#{version}/index.html\">#{version}#{badge}</a></li>\n"
    end

    html += <<~HTML
        </ul>

        <p class="description">
          <a href="https://github.com/funes-org/funes">View on GitHub</a> |
          <a href="https://funes.org/">Official Website</a>
        </p>
      </body>
      </html>
    HTML

    File.write("docs/index.html", html)
    puts "Version index page created at docs/index.html"
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
