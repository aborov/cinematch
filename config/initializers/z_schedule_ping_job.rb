# frozen_string_literal: true

# This initializer is named with a 'z_' prefix to ensure it loads after other initializers
# It schedules the ping job for the JRuby service

Rails.application.config.after_initialize do
  # Only schedule the ping job in production and if we're not running on JRuby
  if Rails.env.production? && RUBY_ENGINE != 'jruby' && defined?(PingJrubyServiceJob)
    begin
      Rails.logger.info "Scheduling PingJrubyServiceJob from initializer"
      PingJrubyServiceJob.schedule_ping
    rescue => e
      Rails.logger.error "Failed to schedule PingJrubyServiceJob: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
end 
