#!/bin/bash
set -e

# Script to run the JRuby service locally for development and testing

echo "Starting JRuby service locally..."

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

# Set up environment variables for JRuby
export JRUBY_OPTS="--dev -J-Xmx400m"
export MEMORY_THRESHOLD_MB=350
export MAX_BATCH_SIZE=50
export BATCH_SIZE=20
export MIN_BATCH_SIZE=3
export PROCESSING_BATCH_SIZE=5
export PORT=3001
export RAILS_ENV=development

# Start the JRuby web server (which also processes jobs in inline mode)
echo "Starting JRuby web server on port $PORT..."
bundle exec rails server -p $PORT

echo "JRuby service stopped." 
