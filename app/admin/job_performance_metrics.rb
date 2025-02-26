ActiveAdmin.register JobPerformanceMetric do
  menu priority: 3, label: "Job Metrics"
  
  filter :job_type
  filter :created_at
  
  index do
    column :job_type
    column :peak_memory_mb
    column :average_memory_mb
    column :duration_seconds
    column :items_processed
    column :created_at
    
    column "Memory Chart" do |metric|
      render partial: 'admin/metrics/memory_chart', locals: { metric: metric }
    end
  end
  
  sidebar "Memory Usage Summary", only: :index do
    div do
      render partial: 'admin/metrics/memory_summary'
    end
  end
end 
