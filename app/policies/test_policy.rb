# frozen_string_literal: true

# Policy for test controller
class TestPolicy < ApplicationPolicy
  def test_fetcher_job?
    # Allow anyone to access this test endpoint
    true
  end
end 
