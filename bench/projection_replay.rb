# Projection replay throughput benchmark
#
# Measures how many SnapshotProjection replays/sec at stream depths 1, 5, 10, 25, 50, 100.
# The `compare!` output shows both absolute ips and relative ratios -- ratios are
# machine-independent and are the primary result to communicate externally.
#
# Run locally:
#   FUNES_BENCH=1 bundle exec bin/rails runner bench/projection_replay.rb
#
# Run in Docker (reproducible absolute numbers):
#   docker run --rm --cpus=1 --memory=512m funes-bench \
#     bin/rails runner bench/projection_replay.rb

require_relative "support/bench_helper"

puts "=== Funes Projection Replay Benchmark ==="
puts "Ruby #{RUBY_VERSION} / Rails #{Rails.version}"
puts "Depths: #{Bench::StreamSeeder::DEPTHS.join(', ')}"
puts

Bench::StreamSeeder.cleanup!

puts "Seeding streams..."
streams = Bench::StreamSeeder.seed_all
GC.compact

puts "Benchmarking projection replay (warmup: 5s, measurement: 10s each)...\n\n"

Benchmark.ips do |x|
  x.config(warmup: 5, time: 10)

  Bench::StreamSeeder::DEPTHS.each do |depth|
    idx = streams[depth]
    x.report("depth #{depth.to_s.rjust(3)}") do
      stream = Examples::DepositEventStream.for(idx)
      stream.projected_with(Examples::Deposit::SnapshotProjection)
    end
  end

  x.compare!
end

Bench::StreamSeeder.cleanup!
