class DropJobPerformanceMetrics < ActiveRecord::Migration[7.1]
  def change
    drop_table :job_performance_metrics do |t|
      t.references :good_job, type: :uuid
      t.string :job_type
      t.float :peak_memory_mb
      t.float :average_memory_mb
      t.integer :duration_seconds
      t.integer :items_processed
      t.jsonb :batch_sizes
      t.timestamps
    end
  end
end
