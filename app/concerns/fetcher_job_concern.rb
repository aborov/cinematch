# frozen_string_literal: true

# Concern for marking jobs to run on the fetcher service
module FetcherJobConcern
  extend ActiveSupport::Concern

  included do
    class_attribute :fetcher_job, default: false
  end

  class_methods do
    # Mark this job to run on the fetcher service
    def runs_on_fetcher
      self.fetcher_job = true
    end
  end
end 
