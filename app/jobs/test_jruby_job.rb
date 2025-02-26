# frozen_string_literal: true

# Test job for verifying JRuby routing
class TestJRubyJob < JrubyCompatibleJob
  queue_as :default

  def perform(test_argument)
    Rails.logger.info "TestJRubyJob started with argument: #{test_argument}"
    
    # Simulate some memory-intensive work
    sleep 2
    
    # Log completion
    Rails.logger.info "TestJRubyJob completed successfully"
  end
end 
