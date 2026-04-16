# Event append throughput benchmark
#
# Measures the cost of appending a Withdrawn event to a stream with N existing events.
# The write path runs the consistency projection (a full O(n) replay) before acquiring
# the write lock, plus two transactional projections (Snapshot + LastActivity).
#
# Each depth is re-seeded per iteration to hold starting depth constant.
#
# Run locally:
#   FUNES_BENCH=1 bundle exec bin/rails runner bench/event_append.rb
#
# Run in Docker (reproducible absolute numbers):
#   docker run --rm --cpus=1 --memory=512m funes-bench \
#     bin/rails runner bench/event_append.rb

require_relative "support/bench_helper"

DEPTHS = Bench::StreamSeeder::DEPTHS
APPEND_ITERATIONS = 10

puts "=== Funes Event Append Benchmark ==="
puts "Ruby #{RUBY_VERSION} / Rails #{Rails.version}"
puts "Depths: #{DEPTHS.join(', ')} (#{APPEND_ITERATIONS} iterations each)"
puts

Bench::StreamSeeder.cleanup!

puts "Benchmarking event append...\n\n"
puts format("  %-14s  %9s  %9s  %9s  %s", "depth", "avg (ms)", "min (ms)", "max (ms)", "vs depth-1")
puts "  #{'─' * 62}"

baseline_avg = nil

DEPTHS.each do |depth|
  GC.compact
  times = []

  APPEND_ITERATIONS.times do |i|
    idx = Bench::StreamSeeder.seed(depth: depth, prefix: "append-#{i}")
    stream = Examples::DepositEventStream.for(idx)

    payment_date = Bench::StreamSeeder::CONTRACT_DATE + (depth + 1).days

    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stream.append(
      Examples::DepositEvents::Withdrawn.new(
        amount: Bench::StreamSeeder::WITHDRAWAL_AMOUNT,
        effective_date: payment_date
      )
    )
    times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) * 1000
  end

  avg = times.sum / times.size
  baseline_avg ||= avg
  ratio = avg / baseline_avg

  puts format("  depth %-8d  %9.2f  %9.2f  %9.2f  %.2fx",
    depth, avg, times.min, times.max, ratio)
end

puts

Bench::StreamSeeder.cleanup!
