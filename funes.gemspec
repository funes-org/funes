require_relative "lib/funes/version"

Gem::Specification.new do |spec|
  spec.name        = "funes-rails"
  spec.version     = Funes::VERSION
  spec.authors     = [ "Vinícius Almeida da Silva" ]
  spec.homepage    = "https://funes.org/"
  spec.summary     = "Rails event sourcing framework"
  spec.description = "A comprehensive event sourcing framework for Rails applications"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/funes-org/funes"
  spec.metadata["changelog_uri"] = "https://github.com/funes-org/funes"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.0.2.1"
end
