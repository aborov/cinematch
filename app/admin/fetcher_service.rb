ActiveAdmin.register_page "Fetcher Service" do
  menu priority: 3, label: "Fetcher Service"

  page_action :wake, method: :post do
    response = FetcherServiceClient.wake
    
    if response.is_a?(Hash) && !response[:error]
      redirect_to admin_fetcher_service_path, notice: "Fetcher service awakened successfully"
    else
      redirect_to admin_fetcher_service_path, alert: "Failed to wake fetcher service: #{response[:error]}"
    end
  rescue => e
    redirect_to admin_fetcher_service_path, alert: "Error waking fetcher service: #{e.message}"
  end
  
  page_action :test_job, method: :post do
    provider = params[:provider] || 'tmdb'
    batch_size = params[:batch_size].to_i || 5
    
    # Use JobRoutingService to route the job to the fetcher service
    job = JobRoutingService.enqueue(FetchContentJob, provider, batch_size)
    
    if job
      redirect_to admin_fetcher_service_path, notice: "Test job started successfully with ID: #{job.id}"
    else
      redirect_to admin_fetcher_service_path, alert: "Failed to start test job"
    end
  rescue => e
    redirect_to admin_fetcher_service_path, alert: "Error starting test job: #{e.message}"
  end

  content title: "Fetcher Service Management" do
    div class: "fetcher-service-management" do
      render partial: 'admin/fetcher_service/index'
    end
  end

  controller do
    def index
      @fetcher_url = ENV['FETCHER_SERVICE_URL']
      @fetcher_status = fetch_status
      @pending_jobs = fetch_pending_jobs
      @recent_jobs = fetch_recent_jobs
    end
    
    private
    
    def fetch_status
      response = FetcherServiceClient.status
      
      if response.is_a?(Hash) && !response[:error]
        response
      else
        { error: response[:error] || "Failed to fetch status" }
      end
    rescue => e
      { error: "Error fetching status: #{e.message}" }
    end
    
    def fetch_pending_jobs
      GoodJob::Job.where(job_class: JobRoutingService::FETCHER_JOBS.join("','"))
                  .where(performed_at: nil)
                  .order(created_at: :desc)
                  .limit(10)
    end
    
    def fetch_recent_jobs
      GoodJob::Job.where(job_class: JobRoutingService::FETCHER_JOBS.join("','"))
                  .where.not(performed_at: nil)
                  .order(created_at: :desc)
                  .limit(10)
    end
  end
end 
