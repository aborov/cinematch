#!/usr/bin/env ruby
# Script to simulate a separate JRuby service in development

require 'fileutils'
require 'json'

# Create a flag file to indicate the JRuby service is running
FileUtils.touch('tmp/jruby_test/jruby_service_running.flag')

puts "=== JRuby Service Simulator ==="
puts "This script simulates a separate JRuby service in development."
puts "It will monitor for jobs in the JRuby queues and process them."
puts "Press Ctrl+C to stop the service."
puts "=== Starting JRuby Service ==="

# Create a file to log wake-up calls
FileUtils.touch('tmp/jruby_test/jruby_wakeups.log')
File.open('tmp/jruby_test/jruby_wakeups.log', 'a') do |f|
  f.puts "#{Time.now} - JRuby service started"
end

# Simulate the JRuby service being "asleep"
@awake = false
@last_activity = Time.now

# Method to "wake up" the service
def wake_up
  return if @awake
  
  puts "=== JRuby Service Waking Up ==="
  # Simulate a delay for waking up
  sleep(3)
  @awake = true
  @last_activity = Time.now
  
  File.open('tmp/jruby_test/jruby_wakeups.log', 'a') do |f|
    f.puts "#{Time.now} - JRuby service woke up"
  end
end

# Method to check if the service should go to sleep
def check_sleep
  if @awake && Time.now - @last_activity > 60 # Sleep after 1 minute of inactivity
    puts "=== JRuby Service Going to Sleep ==="
    @awake = false
    
    File.open('tmp/jruby_test/jruby_wakeups.log', 'a') do |f|
      f.puts "#{Time.now} - JRuby service went to sleep"
    end
  end
end

# Method to handle ping requests
def handle_ping
  wake_up
  @last_activity = Time.now
  
  File.open('tmp/jruby_test/jruby_wakeups.log', 'a') do |f|
    f.puts "#{Time.now} - JRuby service received ping"
  end
  
  puts "=== JRuby Service Pinged ==="
end

# Method to check for jobs in the JRuby queues
def check_for_jobs
  # In a real implementation, this would query the database
  # For simulation, we'll check if a file exists
  if File.exist?('tmp/jruby_test/pending_job.json')
    wake_up
    
    # Read the job details
    job_data = JSON.parse(File.read('tmp/jruby_test/pending_job.json'))
    
    puts "=== Processing Job: #{job_data['job_class']} ==="
    puts "Job ID: #{job_data['job_id']}"
    puts "Arguments: #{job_data['arguments']}"
    
    # Simulate job processing
    sleep(2)
    
    # Mark the job as processed
    FileUtils.rm('tmp/jruby_test/pending_job.json')
    
    File.open('tmp/jruby_test/jruby_wakeups.log', 'a') do |f|
      f.puts "#{Time.now} - Processed job: #{job_data['job_class']}"
    end
    
    puts "=== Job Completed ==="
    @last_activity = Time.now
  end
end

# Main loop
begin
  while true
    # Check if we need to wake up for a ping
    if File.exist?('tmp/jruby_test/ping_request.flag')
      handle_ping
      FileUtils.rm('tmp/jruby_test/ping_request.flag')
    end
    
    # Check for jobs
    check_for_jobs
    
    # Check if we should go to sleep
    check_sleep
    
    # Sleep briefly to avoid high CPU usage
    sleep(1)
  end
rescue Interrupt
  puts "=== JRuby Service Shutting Down ==="
  FileUtils.rm('tmp/jruby_test/jruby_service_running.flag') if File.exist?('tmp/jruby_test/jruby_service_running.flag')
end 
