#!/usr/bin/env ruby
# Script to simulate the main app's job routing

require 'fileutils'
require 'json'
require 'optparse'

# Parse command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: ruby simulate_job_routing.rb [options]"

  opts.on("-j", "--job-class JOB_CLASS", "Job class to enqueue") do |job_class|
    options[:job_class] = job_class
  end

  opts.on("-a", "--args ARGS", "Job arguments (JSON string)") do |args|
    options[:args] = JSON.parse(args)
  end

  opts.on("-p", "--ping", "Just ping the JRuby service") do
    options[:ping] = true
  end

  opts.on("-h", "--help", "Show this help message") do
    puts opts
    exit
  end
end.parse!

# Default job class and arguments
options[:job_class] ||= "FetchContentJob"
options[:args] ||= { "fetch_new" => true }

# Method to check if the JRuby service is running
def jruby_service_running?
  File.exist?('tmp/jruby_test/jruby_service_running.flag')
end

# Method to ping the JRuby service
def ping_jruby_service
  puts "Pinging JRuby service..."
  
  # Create a flag file to request a ping
  FileUtils.touch('tmp/jruby_test/ping_request.flag')
  
  # Wait for the service to process the ping
  sleep(0.5)
  
  if jruby_service_running?
    puts "JRuby service is running."
    true
  else
    puts "JRuby service is not running."
    false
  end
end

# Method to enqueue a job
def enqueue_job(job_class, args)
  puts "Enqueuing job: #{job_class}"
  puts "Arguments: #{args.inspect}"
  
  # First, ping the JRuby service to wake it up
  ping_success = ping_jruby_service
  
  if !ping_success
    puts "Failed to wake up JRuby service. Job will be enqueued anyway."
  end
  
  # Create a job file
  job_data = {
    'job_class' => job_class,
    'job_id' => "job_#{Time.now.to_i}",
    'arguments' => args
  }
  
  File.open('tmp/jruby_test/pending_job.json', 'w') do |f|
    f.write(JSON.pretty_generate(job_data))
  end
  
  puts "Job enqueued successfully."
end

# Main execution
if options[:ping]
  ping_jruby_service
else
  enqueue_job(options[:job_class], options[:args])
end 
