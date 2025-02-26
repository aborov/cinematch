# frozen_string_literal: true

class SimpleTestJob < ApplicationJob
  queue_as :default

  def perform(test_argument)
    Rails.logger.info "SimpleTestJob started with argument: #{test_argument}"
    
    # Simulate some work
    sleep 2
    
    # Log completion
    Rails.logger.info "SimpleTestJob completed successfully"
  end
end 
