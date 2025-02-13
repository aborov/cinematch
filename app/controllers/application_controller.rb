# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include UserActivityTracking
  after_action :verify_authorized, unless: :skip_authorization?
  # Ensure unauthorized access is handled
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  protect_from_forgery with: :exception
  before_action :set_csrf_cookie
  before_action :store_user_location!, if: :storable_location?
  before_action :configure_permitted_parameters, if: :devise_controller?, unless: :confirmations_controller?
  before_action :check_user_setup, if: :user_signed_in?

  private

  def user_not_authorized
    flash[:alert] = 'You are not authorized to perform this action.'
    redirect_to(request.referrer || root_path)
  end

  def skip_authorization?
    devise_controller? || pages_controller? || is_a?(ActiveAdmin::BaseController) || self.class.ancestors.include?(ActiveAdmin::BaseController)
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

  def set_watchlist_count
    @watchlist_count = current_user&.watchlist_items&.where(watched: false)&.count || 0
  end

  def storable_location?
    request.get? && 
    is_navigational_format? && 
    !request.xhr? && 
    !devise_controller? && 
    !request.path.start_with?('/watchlist/') # Exclude all watchlist AJAX endpoints
  end

  def store_user_location!
    store_location_for(:user, request.fullpath)
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || recommendations_path
  end

  def check_user_setup
    return if devise_controller? || 
              controller_name == 'surveys' || 
              !user_signed_in? ||
              request.path == destroy_user_session_path ||
              request.xhr? # Skip for AJAX requests

    unless current_user.confirmed?
      redirect_to edit_user_registration_path, 
                  alert: "Please check your email (#{current_user.email}) and click the confirmation link to verify your account. " \
                         "If you didn't receive the email, you can request a new one below."
      return
    end

    if current_user.survey_responses.empty?
      redirect_to surveys_path(type: 'basic'), notice: "Please complete the basic survey to get started."
    end
  end

  def confirmations_controller?
    controller_name == 'confirmations'
  end
end
