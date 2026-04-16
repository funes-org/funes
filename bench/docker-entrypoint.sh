#!/usr/bin/env bash
set -e

# Ensure the test database schema is up to date before running any benchmark.
bundle exec bin/rails app:db:prepare

exec bundle exec "$@"
