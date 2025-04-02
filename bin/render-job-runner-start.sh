#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Starting job runner service..."

# Set environment variables
export JOB_RUNNER_ONLY=true
export RAILS_ENV=job_runner
export PORT=${PORT:-3000}

# Print environment info for debugging
echo "Running in RAILS_ENV: $RAILS_ENV"
echo "Using PORT: $PORT"
echo "JOB_RUNNER_ONLY: $JOB_RUNNER_ONLY"

# Start the server with minimal configuration
# Use custom Puma configuration for job runner
bundle exec puma -C config/puma_job_runner.rb
