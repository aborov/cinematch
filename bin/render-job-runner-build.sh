#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Starting job runner build script..."

# Set environment variables
export RAILS_ENV=job_runner
export JOB_RUNNER_ONLY=true

# Install dependencies
bundle install

# Migrate database if needed
bundle exec rake db:migrate

# Skip asset compilation completely
echo "Skipping asset compilation for job runner service"

# Create necessary directories
mkdir -p tmp/pids
mkdir -p log

# Clear any temporary files
rm -rf tmp/cache

echo "Job runner build completed successfully" 
