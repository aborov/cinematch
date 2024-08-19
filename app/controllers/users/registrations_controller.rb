# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    before_action :configure_permitted_parameters, if: :devise_controller?

    protected

    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:sign_up, keys: %i[name gender dob])
      devise_parameter_sanitizer.permit(:account_update, keys: %i[name gender dob])
    end

    def update_resource(resource, params)
      if params[:password].blank? && params[:password_confirmation].blank?
        params.delete(:current_password)
        resource.update_without_password(params)
      else
        resource.update_with_password(params)
      end
    end
  end
end
