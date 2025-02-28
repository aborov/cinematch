# frozen_string_literal: true

namespace :jruby_service do
  desc "Check the status of the JRuby service"
  task status: :environment do
    status = JobRoutingService.jruby_service_status
    
    puts "JRuby Service Status:"
    puts "====================="
    
    if status.is_a?(Hash)
      if status[:error].present?
        puts "Error: #{status[:error]}"
      else
        status.each do |key, value|
          if key == 'memory' && value.is_a?(Hash)
            puts "Memory:"
            value.each do |mem_key, mem_value|
              puts "  #{mem_key}: #{mem_value}"
            end
          elsif key == 'jobs' && value.is_a?(Hash)
            puts "Jobs:"
            value.each do |job_key, job_value|
              puts "  #{job_key}: #{job_value}"
            end
          elsif key == 'queues' && value.is_a?(Hash)
            puts "Queues:"
            value.each do |queue_name, queue_stats|
              puts "  #{queue_name}:"
              queue_stats.each do |stat_key, stat_value|
                puts "    #{stat_key}: #{stat_value}"
              end
            end
          else
            puts "#{key}: #{value}"
          end
        end
      end
    else
      puts "Unable to get status: #{status.inspect}"
    end
  end
  
  desc "Wake up the JRuby service"
  task wake: :environment do
    puts "Attempting to wake JRuby service..."
    
    success = JobRoutingService.wake_jruby_service_with_retries(5)
    
    if success
      puts "Successfully woke JRuby service!"
      
      # Check status after waking
      Rake::Task["jruby_service:status"].invoke
    else
      puts "Failed to wake JRuby service after multiple attempts."
      puts "Check the logs for more details."
    end
  end
  
  desc "List all jobs that should be routed to JRuby"
  task list_jobs: :environment do
    puts "Jobs configured to run on JRuby:"
    puts "================================"
    
    JobRoutingService::JRUBY_JOBS.each do |job_class_name|
      puts "- #{job_class_name}"
    end
    
    puts "\nQueues configured for JRuby:"
    puts "============================"
    
    JobRoutingService::JRUBY_QUEUES.each do |queue_name|
      puts "- #{queue_name}"
    end
  end
  
  desc "Check if a job is configured to run on JRuby"
  task :check_job, [:job_class] => :environment do |_t, args|
    job_class = args[:job_class]
    
    if job_class.blank?
      puts "Please provide a job class name: rake jruby_service:check_job[FetchContentJob]"
      next
    end
    
    is_jruby_job = JobRoutingService.jruby_job?(job_class)
    
    puts "Job: #{job_class}"
    puts "Configured to run on JRuby: #{is_jruby_job ? 'YES' : 'NO'}"
    
    # Try to get the actual class
    begin
      job_class_obj = job_class.constantize
      
      if job_class_obj.respond_to?(:queue_name)
        queue_name = job_class_obj.queue_name
        puts "Queue name: #{queue_name}"
        puts "Queue is JRuby queue: #{JobRoutingService.jruby_queue?(queue_name) ? 'YES' : 'NO'}"
      else
        queue_name = JobRoutingService.determine_queue(job_class)
        puts "Determined queue name: #{queue_name}"
        puts "Queue is JRuby queue: #{JobRoutingService.jruby_queue?(queue_name) ? 'YES' : 'NO'}"
      end
      
      if job_class_obj.included_modules.include?(JrubyJobConcern)
        puts "Includes JrubyJobConcern: YES"
      else
        puts "Includes JrubyJobConcern: NO"
      end
    rescue NameError => e
      puts "Could not find job class: #{e.message}"
    end
  end
  
  desc "Debug job routing for a specific job"
  task :debug_routing, [:job_class] => :environment do |_t, args|
    job_class = args[:job_class]
    
    if job_class.blank?
      puts "Please provide a job class name: rake jruby_service:debug_routing[FetchContentJob]"
      next
    end
    
    puts "Debugging job routing for: #{job_class}"
    puts "===================================="
    
    # Check if it's in the JRUBY_JOBS list
    is_jruby_job = JobRoutingService.jruby_job?(job_class)
    puts "Listed in JRUBY_JOBS: #{is_jruby_job ? 'YES' : 'NO'}"
    
    # Try to get the actual class
    begin
      job_class_obj = job_class.constantize
      
      # Check if it includes JrubyJobConcern
      if job_class_obj.included_modules.include?(JrubyJobConcern)
        puts "Includes JrubyJobConcern: YES"
      else
        puts "Includes JrubyJobConcern: NO"
      end
      
      # Check if it inherits from JrubyCompatibleJob
      if job_class_obj < JrubyCompatibleJob
        puts "Inherits from JrubyCompatibleJob: YES"
      else
        puts "Inherits from JrubyCompatibleJob: NO"
      end
      
      # Check queue name
      if job_class_obj.respond_to?(:queue_name)
        queue_name = job_class_obj.queue_name
        puts "Queue name from class: #{queue_name}"
      else
        queue_name = JobRoutingService.determine_queue(job_class)
        puts "Determined queue name: #{queue_name}"
      end
      
      # Check if queue is in JRUBY_QUEUES
      puts "Queue is in JRUBY_QUEUES: #{JobRoutingService.jruby_queue?(queue_name) ? 'YES' : 'NO'}"
      
      # Check GoodJob configuration
      puts "\nGoodJob Configuration:"
      puts "======================"
      
      # Check if we're running on JRuby
      puts "Running on JRuby: #{RUBY_ENGINE == 'jruby' ? 'YES' : 'NO'}"
      
      # Check execution mode
      puts "Execution mode: #{GoodJob.configuration.execution_mode}"
      
      # Check queues being processed
      puts "Queues being processed: #{GoodJob.configuration.queues}"
      
      # Check max threads
      puts "Max threads: #{GoodJob.configuration.max_threads}"
      
      # Check JRuby service URL
      jruby_url = Rails.application.config.jruby_service_url
      puts "\nJRuby service URL: #{jruby_url.present? ? jruby_url : 'Not configured'}"
      
      # Test job enqueuing
      puts "\nSimulating job enqueuing (not actually enqueuing):"
      puts "================================================="
      
      # Would this job be routed to JRuby?
      if JobRoutingService.jruby_job?(job_class)
        puts "This job would be routed to JRuby"
        puts "Queue that would be used: #{JobRoutingService.determine_queue(job_class)}"
        
        # Would the JRuby service be awakened?
        if jruby_url.present?
          puts "JRuby service would be awakened: YES"
        else
          puts "JRuby service would be awakened: NO (URL not configured)"
        end
      else
        puts "This job would NOT be routed to JRuby"
        puts "Queue that would be used: #{JobRoutingService.determine_queue(job_class)}"
      end
    rescue NameError => e
      puts "Could not find job class: #{e.message}"
    rescue => e
      puts "Error during debugging: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
  
  desc "Enqueue a test job to run on JRuby"
  task test_job: :environment do
    puts "Enqueuing a test job to run on JRuby..."
    
    # Check if TestJrubyJob exists
    begin
      if defined?(TestJrubyJob)
        job = JobRoutingService.enqueue(TestJrubyJob)
        puts "Successfully enqueued TestJrubyJob with ID: #{job.job_id}"
        puts "Check the logs to see if it runs on JRuby"
      else
        puts "TestJrubyJob not found. Creating a temporary test job..."
        
        # Create a temporary test job class
        Object.const_set("TestJrubyJob", Class.new(JrubyCompatibleJob) do
          include JrubyJobConcern
          
          def perform
            Rails.logger.info("TestJrubyJob running on #{RUBY_ENGINE}")
            Rails.logger.info("Memory usage: #{get_memory_usage} MB")
            
            # Sleep for a bit to simulate work
            sleep(5)
            
            Rails.logger.info("TestJrubyJob completed successfully")
          end
        end)
        
        job = JobRoutingService.enqueue(TestJrubyJob)
        puts "Successfully enqueued temporary TestJrubyJob with ID: #{job.job_id}"
        puts "Check the logs to see if it runs on JRuby"
      end
    rescue => e
      puts "Error enqueuing test job: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
end 
