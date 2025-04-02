class JobRunnerController < JobRunnerBaseController
  # Redirect all web requests to the main application
  def index
    if Rails.env.job_runner? && ENV['MAIN_APP_URL'].present?
      redirect_to ENV['MAIN_APP_URL'], allow_other_host: true
    else
      render plain: "Job Runner Service - API Only", status: :ok
    end
  end
  
  # Health check endpoint for monitoring
  def health_check
    render json: { 
      status: 'ok', 
      timestamp: Time.current,
      environment: Rails.env,
      job_runner: ENV['JOB_RUNNER_ONLY'] == 'true'
    }
  end

  # Handle job completion notifications
  def update_recommendations
    # This is just a stub in the job runner environment
    # The actual implementation is in the main app
    render json: { status: 'ok', message: 'Notification received in job runner' }
  end
end 
