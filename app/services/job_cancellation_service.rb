class JobCancellationService
  # Cancel a job by marking it as discarded in the database
  def self.cancel_job(job_id)
    job = GoodJob::Job.find_by(id: job_id)
    return false unless job
    
    # Mark the job as discarded in the database
    job.update(
      finished_at: Time.current, 
      error: "Cancelled by user at #{Time.current}",
      error_event: { 
        error_type: "Cancelled", 
        message: "Job was manually cancelled by admin user"
      }
    )
    
    # Log the cancellation
    Rails.logger.info "Job #{job_id} has been cancelled by admin"
    
    # Return true if the job was successfully cancelled
    true
  end
  
  # Check if a job has been cancelled
  def self.cancelled?(job_id)
    # A job is considered cancelled if it's been discarded or doesn't exist
    job = GoodJob::Job.find_by(id: job_id)
    return true unless job
    
    # Check if the job has been marked as cancelled
    if job.finished_at.present? && job.error.present? && job.error.include?("Cancelled by user")
      Rails.logger.info "Job #{job_id} cancellation check: cancelled"
      return true
    end
    
    false
  end
end 
