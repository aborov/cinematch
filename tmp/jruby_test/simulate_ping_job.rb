#!/usr/bin/env ruby
# Script to simulate the periodic PingJrubyServiceJob

require 'fileutils'
require 'json'

puts "=== Simulating PingJrubyServiceJob ==="
puts "This script will ping the JRuby service every 10 minutes."
puts "Press Ctrl+C to stop."

# Method to check if there are pending jobs
def check_pending_jobs
  # In a real implementation, this would query the database
  # For simulation, we'll check if a file exists
  File.exist?('tmp/jruby_test/pending_job.json')
end

# Method to ping the JRuby service
def ping_jruby_service
  puts "#{Time.now} - Pinging JRuby service..."
  
  # Create a flag file to request a ping
  FileUtils.touch('tmp/jruby_test/ping_request.flag')
  
  # Log the ping
  File.open('tmp/jruby_test/ping_job.log', 'a') do |f|
    f.puts "#{Time.now} - PingJrubyServiceJob executed"
  end
  
  # Check for pending jobs
  if check_pending_jobs
    puts "#{Time.now} - Found pending jobs"
    File.open('tmp/jruby_test/ping_job.log', 'a') do |f|
      f.puts "#{Time.now} - Found pending jobs"
    end
  else
    puts "#{Time.now} - No pending jobs found"
  end
end

# Create log file
FileUtils.touch('tmp/jruby_test/ping_job.log')

# Main loop
begin
  while true
    ping_jruby_service
    
    # Wait for 10 minutes (simulated as 10 seconds for testing)
    puts "Waiting for 10 seconds (simulating 10 minutes)..."
    sleep(10)
  end
rescue Interrupt
  puts "=== Stopping PingJrubyServiceJob Simulation ==="
end 
