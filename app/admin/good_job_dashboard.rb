ActiveAdmin.register_page "Good Job Dashboard" do
  menu priority: 2, label: "Job Dashboard"

  content title: "Good Job Dashboard" do
    div class: "good-job-dashboard" do
      render partial: 'admin/good_job/dashboard'
    end
  end

  action_item :fetch_content do
    link_to 'Fetch Content', admin_good_job_dashboard_run_fetch_content_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to start a content fetch job?' }
  end

  action_item :update_recommendations do
    link_to 'Update Recommendations', admin_good_job_dashboard_run_update_recommendations_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to update recommendations for all users?' }
  end

  action_item :fill_missing_details do
    link_to 'Fill Missing Details', admin_good_job_dashboard_run_fill_missing_details_path, 
            method: :post, 
            class: 'admin-job-button',
            data: { confirm: 'Are you sure you want to fill missing content details?' }
  end

  page_action :run_fetch_content, method: :post do
    authorize :page, :run_fetch_content?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob')
    else
      job = FetchContentJob.perform_later
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Content fetch job started (Job ID: #{job_id})"
  end

  page_action :run_fetch_new_content, method: :post do
    authorize :page, :run_fetch_new_content?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob', { fetch_new: true })
    else
      job = FetchContentJob.perform_later(fetch_new: true)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Fetch new content job started (Job ID: #{job_id})"
  end

  page_action :run_update_existing_content, method: :post do
    authorize :page, :run_update_existing_content?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob', { update_existing: true })
    else
      job = FetchContentJob.perform_later(update_existing: true)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Update existing content job started (Job ID: #{job_id})"
  end

  page_action :run_fill_missing_content_details, method: :post do
    authorize :page, :run_fill_missing_content_details?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FetchContentJob', { fill_missing: true })
    else
      job = FetchContentJob.perform_later(fill_missing: true)
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Fill missing content details job started (Job ID: #{job_id})"
  end

  page_action :run_update_recommendations, method: :post do
    authorize :page, :run_update_recommendations?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('UpdateAllRecommendationsJob')
    else
      job = UpdateAllRecommendationsJob.perform_later
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Update recommendations job started (Job ID: #{job_id})"
  end

  page_action :run_fill_missing_details, method: :post do
    authorize :page, :run_fill_missing_details?
    
    # Use JobRunnerService directly instead of perform_later
    job_id = if Rails.env.production? && ENV['JOB_RUNNER_ONLY'] != 'true'
      JobRunnerService.wake_up_job_runner
      JobRunnerService.run_job('FillMissingDetailsJob')
    else
      job = FillMissingDetailsJob.perform_later
      job.job_id
    end
    
    redirect_to admin_good_job_dashboard_path, notice: "Fill missing details job started (Job ID: #{job_id})"
  end

  page_action :delete_job, method: :delete do
    authorize :page, :delete_job?
    
    job_id = params[:id]
    job = GoodJob::Job.find_by(id: job_id)
    
    if job
      job_class = job.job_class
      job.destroy
      redirect_to admin_good_job_dashboard_path, notice: "Job #{job_class} (ID: #{job_id}) has been deleted from history"
    else
      redirect_to admin_good_job_dashboard_path, alert: "Job with ID #{job_id} not found"
    end
  end

  controller do
    helper_method :job_status

    def index
      @jobs = GoodJob::Job.all
      @queues = GoodJob::Job.distinct.pluck(:queue_name).compact.sort
      @next_fetch_job = GoodJob::Job.where(job_class: 'FetchContentJob').scheduled.first
      @next_update_job = GoodJob::Job.where(job_class: 'UpdateAllRecommendationsJob').scheduled.first
      @next_fill_details_job = GoodJob::Job.where(job_class: 'FillMissingDetailsJob').scheduled.first
    end

    private

    def job_status(job)
      return 'Failed' if job.error.present?
      return 'Finished' if job.finished_at
      return 'Running' if job.performed_at
      'Queued'
    end
  end
end
