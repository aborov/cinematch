# frozen_string_literal: true

# Concern to mark jobs that should run on JRuby
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
