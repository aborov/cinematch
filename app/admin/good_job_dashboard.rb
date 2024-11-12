ActiveAdmin.register_page "Good Job Dashboard" do
  menu priority: 2, label: "Job Dashboard"

  content title: "Good Job Dashboard" do
    div class: "good-job-dashboard" do
      render partial: 'admin/good_job/dashboard'
    end
  end

  controller do
    helper_method :job_status

    def index
      @jobs = GoodJob::Job.all
      @queues = GoodJob::Job.distinct.pluck(:queue_name).compact.sort
      @next_fetch_job = GoodJob::Job.where(job_class: 'FetchContentJob').scheduled.first
      @next_update_job = GoodJob::Job.where(job_class: 'UpdateAllRecommendationsJob').scheduled.first
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
