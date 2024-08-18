class ApplicationController < ActionController::Base
  include Pundit::Authorization
  after_action :verify_authorized, unless: :skip_authorization?
  # Ensure unauthorized access is handled
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_to(request.referrer || root_path)
  end

  def skip_authorization?
    devise_controller? || pages_controller?
  end

  def pages_controller?
    controller_name == 'pages'
  end
end
