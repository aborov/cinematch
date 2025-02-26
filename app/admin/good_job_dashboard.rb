ActiveAdmin.register_page "Good Job Dashboard" do
  menu priority: 2, label: "Job Dashboard"

  page_action :show, method: :get, title: "Error Details" do
    @job = GoodJob::Job.find(params[:id])
    render 'admin/good_job/error_details', layout: 'active_admin'
  end

  content title: "Good Job Dashboard" do
    div class: "good-job-dashboard" do
      render partial: 'admin/good_job/dashboard'
    end
  end

  controller do
    helper_method :job_status, :admin_good_job_path, :enqueued_at

    def index
      @jobs = GoodJob::Job.all
      @queues = GoodJob::Job.distinct.pluck(:queue_name).compact.sort
      @next_fetch_job = GoodJob::Job.where(job_class: 'FetchContentJob').scheduled.first
      @next_update_job = GoodJob::Job.where(job_class: 'UpdateAllRecommendationsJob').scheduled.first
    end

    def admin_good_job_path(job)
      admin_good_job_dashboard_show_path(id: job.id)
    end

    def enqueued_at(job)
      return nil unless job.serialized_params
      params = job.serialized_params.is_a?(String) ? JSON.parse(job.serialized_params) : job.serialized_params
      params['enqueued_at']&.to_time&.strftime('%Y-%m-%d %H:%M:%S')
    rescue JSON::ParserError
      nil
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
