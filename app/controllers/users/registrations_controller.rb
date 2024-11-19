# frozen_string_literal: true

module Users
  class RegistrationsController < Devise::RegistrationsController
    before_action :configure_permitted_parameters, if: :devise_controller?
    prepend_before_action :check_captcha, only: [:create]

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

    def sign_up_params
      params = super
      if params[:dob].blank?
        raise ActionController::ParameterMissing.new(:dob)
      end
      params
    end

    private

    def check_captcha
      return if verify_recaptcha

      self.resource = resource_class.new sign_up_params
      resource.validate
      set_minimum_password_length
      respond_with_navigational(resource) { render :new }
    end
  end
end
