# CPU flamegraph for SnapshotProjection replay
#
# Profiles 1,000 replay iterations on a depth-50 stream.
# Shows the time split between: SQLite query, ActiveRecord result mapping,
# Ruby projection logic, and event deserialization.
#
# Run locally:
#   FUNES_BENCH=1 bundle exec bin/rails runner bench/profile_replay.rb
#   stackprof --d3-flamegraph bench/tmp/stackprof-replay-50.dump > bench/tmp/flamegraph.html
#   open bench/tmp/flamegraph.html
#
# Run in Docker (volume-mount bench/tmp/ to retrieve the dump):
#   docker run --rm --cpus=1 --memory=512m \
#     -v "$(pwd)/bench/tmp:/funes/bench/tmp" funes-bench \
#     bin/rails runner bench/profile_replay.rb

require "stackprof"
require_relative "support/bench_helper"

PROFILE_DEPTH      = 50
PROFILE_ITERATIONS = 1_000
DUMP_PATH          = File.expand_path("tmp/stackprof-replay-#{PROFILE_DEPTH}.dump", __dir__)

FileUtils.mkdir_p(File.dirname(DUMP_PATH))

puts "=== Funes StackProf: Projection Replay at depth #{PROFILE_DEPTH} ==="
puts "Ruby #{RUBY_VERSION} / Rails #{Rails.version}"
puts

Bench::StreamSeeder.cleanup!

puts "Seeding depth-#{PROFILE_DEPTH} stream..."
idx = Bench::StreamSeeder.seed(depth: PROFILE_DEPTH, prefix: "profile")

puts "Warming up (50 iterations)..."
50.times { Examples::DepositEventStream.for(idx).projected_with(Examples::Deposit::SnapshotProjection) }
GC.compact

puts "Profiling #{PROFILE_ITERATIONS} replays at depth #{PROFILE_DEPTH}...\n\n"

StackProf.run(mode: :cpu, out: DUMP_PATH, interval: 100, raw: true) do
  PROFILE_ITERATIONS.times do
    Examples::DepositEventStream.for(idx).projected_with(Examples::Deposit::SnapshotProjection)
  end
end

report = StackProf::Report.new(Marshal.load(File.binread(DUMP_PATH)))

puts "Top 20 methods by self time:\n\n"
report.print_text(false, 20)

puts "\nDump written to: #{DUMP_PATH}"
puts "\nNext steps:"
puts "  stackprof --d3-flamegraph #{DUMP_PATH} > bench/tmp/flamegraph.html"
puts "  open bench/tmp/flamegraph.html"

Bench::StreamSeeder.cleanup!
