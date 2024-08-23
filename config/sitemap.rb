# Set the host name for URL creation
SitemapGenerator::Sitemap.default_host = "https://cinematch.net"

# Use the `create` method on the `SitemapGenerator::Interpreter` class 
SitemapGenerator::Interpreter.send :include, Rails.application.routes.url_helpers

SitemapGenerator::Interpreter.new.instance_eval do
  # Add root path
  add '/', changefreq: 'daily', priority: 0.9

  # Add static pages
  add '/contact', changefreq: 'monthly', priority: 0.3
  add '/terms', changefreq: 'monthly', priority: 0.3
  add '/privacy', changefreq: 'monthly', priority: 0.3
  add '/data_deletion', changefreq: 'monthly', priority: 0.3

  # Add dynamic pages
  add recommendations_path, changefreq: 'daily', priority: 0.7
  add surveys_path, changefreq: 'weekly', priority: 0.6

  # Add user profiles (if they're public)
  User.find_each do |user|
    add user_path(user), changefreq: 'weekly', priority: 0.5
  end
end
