#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Starting job runner build script..."

# Install dependencies
bundle install

# Migrate database if needed
bundle exec rake db:migrate

# Skip asset compilation completely
echo "Skipping asset compilation for job runner service"

# Clear any temporary files
rm -rf tmp/cache

echo "Job runner build completed successfully" 
