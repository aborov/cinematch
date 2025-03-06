#!/bin/bash
# Script to test asset precompilation

echo "Testing asset precompilation..."
RAILS_ENV=production bundle exec rails assets:precompile

if [ $? -eq 0 ]; then
  echo "Asset precompilation successful!"
  exit 0
else
  echo "Asset precompilation failed!"
  exit 1
fi 
