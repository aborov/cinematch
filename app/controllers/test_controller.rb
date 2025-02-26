# frozen_string_literal: true

# Test controller for verifying JRuby routing
class TestController < ApplicationController
  skip_before_action :verify_authenticity_token

  def test_jruby_job
    # Skip authorization for this test endpoint
    authorize :test, :test_jruby_job?
    
    # Enqueue the test job
    TestJRubyJob.perform_later('test argument from controller')
    
    # Return a simple response
    render json: { status: 'ok', message: 'TestJRubyJob enqueued' }
  end
end 
