namespace :job_runner do
  desc "Check the status of the job runner service"
  task status: :environment do
    require 'httparty'
    
    puts "Checking job runner status..."
    
    if ENV['JOB_RUNNER_ONLY'] == 'true'
      puts "This is the job runner instance."
      puts "Environment: #{Rails.env}"
      puts "Good Job status: #{GoodJob::Job.count >= 0 ? 'connected' : 'error'}"
      puts "Active jobs: #{GoodJob::Job.where.not(performed_at: nil).where(finished_at: nil).count}"
      puts "Queued jobs: #{GoodJob::Job.where(performed_at: nil).count}"
      
      # Show recent errors
      recent_errors = GoodJob::Job.where.not(error: nil).order(created_at: :desc).limit(5)
      if recent_errors.any?
        puts "\nRecent errors:"
        recent_errors.each do |job|
          puts "- #{job.job_class} (#{job.id}): #{job.error.to_s.truncate(100)}"
        end
      else
        puts "No recent errors."
      end
    else
      # Check if the job runner is available
      job_runner_url = ENV.fetch('JOB_RUNNER_URL', 'https://cinematch-job-runner.onrender.com')
      puts "Checking job runner at #{job_runner_url}..."
      
      begin
        response = HTTParty.get(
          "#{job_runner_url}/health_check",
          timeout: 10
        )
        
        if response.success?
          puts "Job runner is available!"
          puts "Response: #{response.body}"
        else
          puts "Job runner returned an error. Status: #{response.code}"
          puts "Response: #{response.body}"
        end
      rescue => e
        puts "Error connecting to job runner: #{e.message}"
      end
      
      # Check the status endpoint
      puts "\nChecking detailed status..."
      begin
        response = HTTParty.get(
          "#{job_runner_url}/api/job_runner/status",
          timeout: 10
        )
        
        if response.success?
          status = response.parsed_response
          puts "Status: #{status['status']}"
          puts "Timestamp: #{status['timestamp']}"
          puts "Environment: #{status['environment']}"
          puts "Good Job status: #{status['good_job_status']}"
          
          if status['active_jobs']
            puts "Active jobs: #{status['active_jobs']}"
            puts "Queued jobs: #{status['queued_jobs']}"
          end
          
          if status['recent_errors'] && status['recent_errors'].any?
            puts "\nRecent errors:"
            status['recent_errors'].each do |error|
              puts "- #{error['job_class']} (#{error['id']}): #{error['error']}"
            end
          end
        else
          puts "Status endpoint returned an error. Status: #{response.code}"
          puts "Response: #{response.body}"
        end
      rescue => e
        puts "Error connecting to status endpoint: #{e.message}"
      end
    end
  end
  
  desc "Wake up the job runner service"
  task wake_up: :environment do
    if ENV['JOB_RUNNER_ONLY'] == 'true'
      puts "This is the job runner instance. No need to wake up."
    else
      puts "Attempting to wake up job runner..."
      
      if JobRunnerService.wake_up_job_runner(max_retries: 3)
        puts "Job runner is awake and healthy!"
      else
        puts "Failed to wake up job runner after multiple attempts."
      end
    end
  end
  
  desc "Restart a stuck job"
  task :restart_job, [:job_id] => :environment do |t, args|
    job_id = args[:job_id]
    
    if job_id.blank?
      puts "Please provide a job ID: rake job_runner:restart_job[job_id]"
      exit 1
    end
    
    job = GoodJob::Job.find_by(id: job_id)
    
    if job.nil?
      puts "Job not found with ID: #{job_id}"
      exit 1
    end
    
    puts "Found job: #{job.job_class} (#{job.id})"
    puts "Status: #{job.finished_at ? 'Finished' : (job.performed_at ? 'Running' : 'Queued')}"
    puts "Error: #{job.error}" if job.error.present?
    
    if job.performed_at.present? && job.finished_at.nil?
      puts "Job appears to be stuck in running state."
      
      print "Do you want to restart this job? (y/n): "
      response = STDIN.gets.chomp.downcase
      
      if response == 'y'
        # Create a new job with the same parameters
        job_class = job.job_class.constantize
        serialized_params = job.serialized_params
        
        # Extract arguments from serialized params
        args = serialized_params['arguments'].first if serialized_params['arguments'].is_a?(Array)
        
        if args.present?
          puts "Restarting job with arguments: #{args.inspect}"
          new_job = job_class.perform_later(args)
        else
          puts "Restarting job without arguments"
          new_job = job_class.perform_later
        end
        
        puts "New job created with ID: #{new_job.job_id}"
        
        # Mark the old job as finished with an error
        job.update(
          finished_at: Time.current,
          error: "Job manually restarted at #{Time.current}. New job ID: #{new_job.job_id}"
        )
        
        puts "Old job marked as finished."
      else
        puts "Operation cancelled."
      end
    else
      puts "Job is not in a running state. No action needed."
    end
  end
end 
