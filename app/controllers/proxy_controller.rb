class ProxyController < ApplicationController
  # Authorization skipping is handled in ApplicationController#skip_authorization?

  def image
    url = params[:url]
    if url.present? && url.start_with?('https://image.tmdb.org/')
      response = HTTP.get(url)
      send_data response.body.to_s, content_type: response.content_type
    else
      head :bad_request
    end
  end
end 
