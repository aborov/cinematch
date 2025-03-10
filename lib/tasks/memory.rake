# frozen_string_literal: true

namespace :memory do
  desc "Monitor memory usage and log it"
  task monitor: :environment do
    begin
      # Get memory usage in MB
      memory_usage = if RUBY_PLATFORM =~ /linux/
        # On Linux, use /proc/self/status
        `cat /proc/self/status | grep VmRSS`.to_s.split[1].to_i / 1024.0
      elsif RUBY_PLATFORM =~ /darwin/
        # On macOS, use ps
        `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
      else
        # Fallback to Ruby's memory reporting
        require 'get_process_mem'
        GetProcessMem.new.mb rescue 0
      end
      
      memory_usage = memory_usage.round
      
      # Only log to console if run directly, not from a callback
      puts "[MemoryMonitor] Current memory usage: #{memory_usage} MB" if ARGV.include?('memory:monitor')
      Rails.logger.info "[MemoryMonitor] Current memory usage: #{memory_usage} MB"
      
      # If memory usage is too high, run garbage collection
      if memory_usage > 500
        # Only log to console if run directly, not from a callback
        puts "[MemoryMonitor] Memory usage is high (#{memory_usage} MB), running garbage collection" if ARGV.include?('memory:monitor')
        Rails.logger.warn "[MemoryMonitor] Memory usage is high (#{memory_usage} MB), running garbage collection"
        
        GC.start
        GC.compact if GC.respond_to?(:compact)
        
        # Check memory usage after garbage collection
        new_memory_usage = if RUBY_PLATFORM =~ /linux/
          `cat /proc/self/status | grep VmRSS`.to_s.split[1].to_i / 1024.0
        elsif RUBY_PLATFORM =~ /darwin/
          `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
        else
          require 'get_process_mem'
          GetProcessMem.new.mb rescue 0
        end
        
        new_memory_usage = new_memory_usage.round
        
        # Only log to console if run directly, not from a callback
        puts "[MemoryMonitor] Memory usage after GC: #{new_memory_usage} MB (reduced by #{memory_usage - new_memory_usage} MB)" if ARGV.include?('memory:monitor')
        Rails.logger.info "[MemoryMonitor] Memory usage after GC: #{new_memory_usage} MB (reduced by #{memory_usage - new_memory_usage} MB)"
      end
    rescue => e
      # Only log to console if run directly, not from a callback
      puts "[MemoryMonitor] Error monitoring memory: #{e.message}" if ARGV.include?('memory:monitor')
      Rails.logger.error "[MemoryMonitor] Error monitoring memory: #{e.message}\n#{e.backtrace.join("\n")}"
    end
  end
end 
