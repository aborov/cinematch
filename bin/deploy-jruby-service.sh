#!/bin/bash
set -e

# Script to deploy the JRuby service to Render

echo "Deploying JRuby service to Render..."

# Ensure we're using JRuby
if command -v rvm &> /dev/null; then
  echo "Using RVM to switch to JRuby..."
  rvm use jruby-9.4.3.0
elif command -v rbenv &> /dev/null; then
  echo "Using rbenv to switch to JRuby..."
  rbenv local jruby-9.4.3.0
else
  echo "No Ruby version manager found. Please ensure JRuby 9.4.3.0 is installed."
fi

# Verify we're using JRuby
ruby_version=$(ruby -v)
if [[ $ruby_version != *"jruby"* ]]; then
  echo "Error: Not using JRuby. Current Ruby version: $ruby_version"
  exit 1
fi

echo "Using Ruby version: $ruby_version"

# Install dependencies
echo "Installing dependencies..."
bundle install

# Copy the JRuby Procfile to the main Procfile
echo "Setting up Procfile for JRuby service..."
cp Procfile.jruby Procfile

# Set up environment variables for JRuby
export JRUBY_OPTS="--dev -J-Xmx400m"
export MEMORY_THRESHOLD_MB=350
export MAX_BATCH_SIZE=50
export BATCH_SIZE=20
export MIN_BATCH_SIZE=3
export PROCESSING_BATCH_SIZE=5

# Deploy to Render
echo "Deploying to Render..."
# Replace with your actual deployment command for Render
# This might be a git push or a Render CLI command
git push render jruby-service:main

echo "JRuby service deployment complete!"
echo "Monitor the deployment at: https://dashboard.render.com" 
