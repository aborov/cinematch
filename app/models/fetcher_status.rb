class FetcherStatus < ApplicationRecord
  validates :provider, presence: true, uniqueness: true
  
  # Update the last run timestamp and status
  def self.update_last_run(provider, status = 'completed')
    record = find_or_initialize_by(provider: provider)
    record.last_run = Time.current
    record.status = status
    record.save!
  end
  
  # Increment the movies fetched count
  def self.increment_movies_fetched(provider, count = 1)
    record = find_or_initialize_by(provider: provider)
    record.movies_fetched = (record.movies_fetched || 0) + count
    record.save!
  end
  
  # Get the last run time for a provider
  def self.last_run_for(provider)
    record = find_by(provider: provider)
    record&.last_run
  end
end 
