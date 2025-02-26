# frozen_string_literal: true

# Test job for verifying JRuby routing
class TestJrubyJob < ApplicationJob
  queue_as :default
  runs_on_jruby

  def perform(test_argument)
    Rails.logger.info "TestJrubyJob started with argument: #{test_argument}"
    
    # Simulate some memory-intensive work
    sleep 2
    
    # Log completion
    Rails.logger.info "TestJrubyJob completed successfully"
  end
end 
