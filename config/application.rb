require_relative "boot"

require "rails/all"
require 'acts_as_list'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module RailsTemplate
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w(assets tasks))

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.generators do |g|
      g.test_framework nil
      g.factory_bot false
      g.scaffold_stylesheet false
      g.stylesheets false
      g.javascripts false
      g.helper false
    end

    # config.action_controller.default_protect_from_forgery = false

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.action_controller.allow_forgery_protection = true

    config.active_job.queue_adapter = :good_job
    
    # Configure allowed hosts
    if ENV['ALLOWED_HOSTS'].present?
      config.hosts = ENV['ALLOWED_HOSTS'].split(',')
    end
  end
end

module Rails
  class << self
    def job_runner?
      env.job_runner?
    end
  end
end

module Rails
  class Env
    def job_runner?
      self == "job_runner".inquiry
    end
  end
end
