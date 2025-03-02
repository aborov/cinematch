#!/usr/bin/env bash
# exit on error
set -o errexit

echo "Deploying to Render..."

# Install dependencies
bundle install

# Precompile assets
bundle exec rake assets:precompile
bundle exec rake assets:clean

# Migrate database
bundle exec rake db:migrate

# Restart services on Render
echo "Deployment completed. Please manually restart both the main app and job runner services on Render."
echo "Visit https://dashboard.render.com/ to restart the services." 
