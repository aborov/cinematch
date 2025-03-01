# frozen_string_literal: true

# Test controller for verifying fetcher service routing
class TestController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_user!
  before_action :require_admin

  def test_fetcher_job
    result = FetcherServiceClient.fetch_movies('tmdb', 5)
    
    render json: {
      message: "Fetcher job started",
      result: result
    }
  end
  
  def run_test_fetcher_job
    job = TestFetcherJob.perform_later('tmdb', 5)
    
    render json: {
      message: "TestFetcherJob enqueued",
      job_id: job.provider_job_id
    }
  end

  private
  
  def require_admin
    unless current_user.admin?
      redirect_to root_path, alert: "You are not authorized to access this page"
    end
  end
end 
