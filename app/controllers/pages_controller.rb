class PagesController < ApplicationController
  layout 'landing', only: [:landing]

  def landing
    if user_signed_in?
      redirect_to recommendations_path
    end
  end
end
