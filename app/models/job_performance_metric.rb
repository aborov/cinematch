# == Schema Information
#
# Table name: job_performance_metrics
#
#  id                :bigint           not null, primary key
#  average_memory_mb :float
#  batch_sizes       :jsonb
#  duration_seconds  :integer
#  items_processed   :integer
#  job_type          :string
#  peak_memory_mb    :float
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  good_job_id       :uuid
#
# Indexes
#
#  index_job_performance_metrics_on_good_job_id              (good_job_id)
#  index_job_performance_metrics_on_job_type_and_created_at  (job_type,created_at)
#
class JobPerformanceMetric < ApplicationRecord
  belongs_to :good_job, class_name: 'GoodJob::Job'
  
  validates :job_type, presence: true
  validates :peak_memory_mb, :average_memory_mb, :duration_seconds, presence: true
  
  scope :recent, -> { where('created_at > ?', 24.hours.ago) }
  scope :by_job_type, ->(type) { where(job_type: type) }

  def self.ransackable_attributes(auth_object = nil)
    %w[
      average_memory_mb
      batch_sizes
      created_at
      duration_seconds
      good_job_id
      id
      items_processed
      job_type
      peak_memory_mb
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["good_job"]
  end
end 
