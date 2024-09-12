ActiveAdmin.register_page "Good Job Dashboard" do
  menu priority: 2, label: "Job Dashboard"

  content title: "Good Job Dashboard" do
    div class: "good-job-dashboard" do
      render partial: 'admin/good_job/dashboard'
    end
  end

  controller do
    def index
      @jobs = GoodJob::Job.all
      @queues = GoodJob::Job.distinct.pluck(:queue_name).compact.sort
    end
  end
end
