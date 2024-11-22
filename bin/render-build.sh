#!/usr/bin/env bash
# exit on error
set -o errexit

# Install ClamAV with sudo
sudo apt-get update
sudo apt-get install -y clamav clamav-daemon
sudo freshclam
sudo mkdir -p /var/lib/clamav
sudo chown -R render:render /var/lib/clamav
sudo service clamav-daemon start

bundle install
bundle exec rake assets:precompile
bundle exec rake assets:clean
bundle exec rake db:migrate
# TODO: remove later, seeding should be manual through shell
bundle exec rake db:seed
bundle exec rake admin:create
