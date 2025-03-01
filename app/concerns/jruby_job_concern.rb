# frozen_string_literal: true

# Concern for marking jobs to run on JRuby
# This will be replaced with FetcherJobConcern
module JrubyJobConcern
  extend ActiveSupport::Concern

  included do
    class_attribute :jruby_job, default: false
  end

  class_methods do
    # Mark this job to run on JRuby
    def runs_on_jruby
      self.jruby_job = true
    end
  end
end 
