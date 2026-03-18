require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  track_files "lib/**/*.rb"
end
