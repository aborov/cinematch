# frozen_string_literal: true

# Test job for the fetcher service
class TestFetcherJob < ApplicationJob
  queue_as :default
  
  # Mark this job to run on the fetcher service
  runs_on_fetcher

  def perform(*args)
    Rails.logger.info("TestFetcherJob started with args: #{args.inspect}")
    
    # Simulate memory-intensive work
    provider = args.first || 'tmdb'
    batch_size = args.second || 5
    
    # Use the fetcher service client to fetch movies
    result = FetcherServiceClient.fetch_movies(provider, batch_size)
    
    Rails.logger.info("TestFetcherJob completed with result: #{result.inspect}")
    
    result
  end
end 
