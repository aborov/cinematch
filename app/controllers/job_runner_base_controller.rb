class JobRunnerBaseController < ActionController::Base
  # Skip CSRF protection for API endpoints
  skip_before_action :verify_authenticity_token
  
  # Skip any user-related concerns
  # This controller is specifically for the job runner service
  # which doesn't need user authentication or tracking
  
  protected
  
  # Helper method to check if we're running in the job runner environment
  def job_runner?
    Rails.env.job_runner? || ENV['JOB_RUNNER_ONLY'] == 'true'
  end
end 
