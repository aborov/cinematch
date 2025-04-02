namespace :recommendations do
  desc "Update recommendations for all users"
  task update_all: :environment do
    batch_size = ENV['BATCH_SIZE'] ? ENV['BATCH_SIZE'].to_i : 50
    puts "Starting to update recommendations for all users with batch size #{batch_size}..."
    
    if ENV['JOB_RUNNER_ONLY'] == 'true'
      puts "Running on job runner, executing locally..."
      UpdateAllRecommendationsJob.new.perform(batch_size: batch_size)
    else
      puts "Running on main app, delegating to job runner..."
      job_id = UpdateAllRecommendationsJob.update_all_recommendations(batch_size: batch_size)
      puts "Job scheduled with ID: #{job_id}"
    end
    
    puts "Recommendation update process initiated."
  end
end 
