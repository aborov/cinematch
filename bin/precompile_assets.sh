#!/bin/bash
# Script to precompile assets with a temporary secret key base

echo "Precompiling assets with temporary secret key base..."
SECRET_KEY_BASE=temporary_key_for_precompilation RAILS_ENV=production bundle exec rails assets:precompile

if [ $? -eq 0 ]; then
  echo "Asset precompilation successful!"
  exit 0
else
  echo "Asset precompilation failed!"
  exit 1
fi 
