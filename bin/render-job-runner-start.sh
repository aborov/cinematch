#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Starting job runner service..."

# Set environment variables
export JOB_RUNNER_ONLY=true
export RAILS_ENV=job_runner

# Start the server with minimal configuration
# Use custom Puma configuration for job runner
bundle exec puma -C config/puma_job_runner.rb
