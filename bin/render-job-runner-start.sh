#!/usr/bin/env bash
# exit on error
set -o errexit

# Start the job runner service
# This will run a minimal Puma server with only the job processing capabilities
bundle exec puma -C config/puma_job_runner.rb 
