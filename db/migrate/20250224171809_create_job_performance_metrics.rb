class CreateJobPerformanceMetrics < ActiveRecord::Migration[7.1]
  def change
    create_table :job_performance_metrics do |t|
      t.references :good_job, type: :uuid
      t.string :job_type
      t.float :peak_memory_mb
      t.float :average_memory_mb
      t.integer :duration_seconds
      t.integer :items_processed
      t.jsonb :batch_sizes
      t.timestamps
    end
    
    add_index :job_performance_metrics, [:job_type, :created_at]
  end
end
