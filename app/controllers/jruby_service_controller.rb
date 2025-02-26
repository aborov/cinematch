# frozen_string_literal: true

# Controller for the JRuby service to handle ping requests and provide status information
class JrubyServiceController < ApplicationController
  # Skip CSRF protection for API endpoints
  skip_before_action :verify_authenticity_token, only: [:ping, :status]
  
  # Simple endpoint to check if the service is running
  def ping
    render json: { status: 'ok', engine: RUBY_ENGINE, version: RUBY_VERSION }
  end
  
  # Provide detailed status information about the JRuby service
  def status
    memory_info = get_memory_info
    
    render json: {
      status: 'ok',
      engine: RUBY_ENGINE,
      version: RUBY_VERSION,
      uptime: process_uptime,
      memory: memory_info,
      jobs: {
        processed: GoodJob::Job.where.not(performed_at: nil).count,
        queued: GoodJob::Job.where(performed_at: nil).count,
        failed: GoodJob::Job.where.not(error: nil).count
      },
      queues: queue_stats
    }
  end
  
  private
  
  # Get memory information
  def get_memory_info
    if RUBY_ENGINE == 'jruby'
      runtime = java.lang.Runtime.getRuntime
      {
        total: (runtime.totalMemory / 1024 / 1024).to_i,
        free: (runtime.freeMemory / 1024 / 1024).to_i,
        used: ((runtime.totalMemory - runtime.freeMemory) / 1024 / 1024).to_i,
        max: (runtime.maxMemory / 1024 / 1024).to_i
      }
    else
      # For MRI Ruby, use the memory_monitor if available
      if defined?(MemoryMonitor)
        monitor = MemoryMonitor.new
        {
          used: monitor.mb.round(1),
          unit: 'MB'
        }
      else
        # Fallback to ps command
        used = `ps -o rss= -p #{Process.pid}`.to_i / 1024.0
        {
          used: used.round(1),
          unit: 'MB'
        }
      end
    end
  end
  
  # Get process uptime
  def process_uptime
    start_time = File.stat("/proc/#{Process.pid}").ctime rescue Time.now - 1
    seconds = (Time.now - start_time).to_i
    
    days = seconds / 86400
    seconds %= 86400
    hours = seconds / 3600
    seconds %= 3600
    minutes = seconds / 60
    seconds %= 60
    
    if days > 0
      "#{days}d #{hours}h #{minutes}m #{seconds}s"
    elsif hours > 0
      "#{hours}h #{minutes}m #{seconds}s"
    elsif minutes > 0
      "#{minutes}m #{seconds}s"
    else
      "#{seconds}s"
    end
  end
  
  # Get queue statistics
  def queue_stats
    queues = {}
    
    # Get all queues
    GoodJob::Job.distinct.pluck(:queue_name).compact.each do |queue|
      queues[queue] = {
        total: GoodJob::Job.where(queue_name: queue).count,
        pending: GoodJob::Job.where(queue_name: queue, performed_at: nil).count,
        processed: GoodJob::Job.where(queue_name: queue).where.not(performed_at: nil).count,
        failed: GoodJob::Job.where(queue_name: queue).where.not(error: nil).count
      }
    end
    
    queues
  end
end 
