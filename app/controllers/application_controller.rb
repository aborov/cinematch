# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  after_action :verify_authorized, unless: :skip_authorization?
  # Ensure unauthorized access is handled
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protect_from_forgery with: :exception
  before_action :set_csrf_cookie

  private

  def user_not_authorized
    flash[:alert] = 'You are not authorized to perform this action.'
    redirect_to(request.referrer || root_path)
  end

  def skip_authorization?
    devise_controller? || pages_controller? || active_admin_controller?
  end

  def active_admin_controller?
    is_a?(ActiveAdmin::BaseController)
  end

  def pages_controller?
    controller_name == 'pages'
  end

  def set_csrf_cookie
    cookies['CSRF-TOKEN'] = form_authenticity_token
  end

  def handle_unverified_request
    flash[:alert] = "CSRF token verification failed. Please try again."
    redirect_to root_path
  end

  def authenticate_admin_user!
    redirect_to root_path, alert: 'Not authorized.' unless current_user&.admin?
  end
end
