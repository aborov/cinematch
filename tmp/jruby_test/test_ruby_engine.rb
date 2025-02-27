#!/usr/bin/env ruby
# Script to test whether a job is running on JRuby or MRI Ruby

puts "=== Ruby Engine Test ==="
puts "This script helps verify which Ruby engine is being used."
puts

# Print Ruby engine information
puts "Ruby Engine: #{RUBY_ENGINE}"
puts "Ruby Version: #{RUBY_VERSION}"
puts "Ruby Platform: #{RUBY_PLATFORM}"

# Check if running on JRuby
if RUBY_ENGINE == 'jruby'
  puts "Running on JRuby!"
  puts "JRuby Version: #{JRUBY_VERSION}" if defined?(JRUBY_VERSION)
  
  # Print JVM information if available
  if defined?(Java)
    runtime = Java.java.lang.Runtime.getRuntime
    max_memory = runtime.maxMemory / 1024 / 1024
    total_memory = runtime.totalMemory / 1024 / 1024
    free_memory = runtime.freeMemory / 1024 / 1024
    used_memory = total_memory - free_memory
    
    puts
    puts "JVM Memory Information:"
    puts "  Max Memory: #{max_memory}MB"
    puts "  Total Memory: #{total_memory}MB"
    puts "  Used Memory: #{used_memory}MB"
    puts "  Free Memory: #{free_memory}MB"
  end
else
  puts "Running on MRI Ruby!"
  
  # Print memory information using ps
  begin
    memory_mb = `ps -o rss= -p #{Process.pid}`.to_i / 1024
    puts
    puts "Memory Information:"
    puts "  Current Memory Usage: #{memory_mb}MB"
  rescue => e
    puts "  Error getting memory information: #{e.message}"
  end
end

puts
puts "=== Test Complete ===" 
