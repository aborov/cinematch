namespace :sitemap do
  desc 'Generate the sitemap'
  task generate: :environment do
    SitemapGenerator::Sitemap.default_host = "https://cinematch.net"
    SitemapGenerator::Sitemap.create
    puts "Sitemap generated successfully."
    SitemapGenerator::Sitemap.ping_search_engines if Rails.env.production?
  end
end
