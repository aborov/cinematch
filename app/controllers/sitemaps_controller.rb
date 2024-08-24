class SitemapsController < ApplicationController
  def show
    sitemap_path = Rails.root.join("public", "sitemaps", "sitemap.xml.gz")
    if File.exist?(sitemap_path)
      send_file(sitemap_path, type: 'application/x-gzip', disposition: 'inline')
    else
      render plain: "Sitemap not found", status: :not_found
    end
  end
end
