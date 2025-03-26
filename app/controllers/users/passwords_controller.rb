# frozen_string_literal: true

module Users
  class PasswordsController < Devise::PasswordsController
    before_action :configure_permitted_parameters, only: [:create]

    def update
      self.resource = resource_class.reset_password_by_token(resource_params)
      resource.skip_age_validation = true
      resource.save

      yield resource if block_given?

      if resource.errors.empty?
        resource.unlock_access! if unlockable?(resource)
        if Devise.sign_in_after_reset_password
          flash_message = resource.active_for_authentication? ? :updated : :updated_not_active
          set_flash_message!(:notice, flash_message)
          resource.after_database_authentication
          sign_in(resource_name, resource)
        else
          set_flash_message!(:notice, :updated_not_active)
        end
        respond_with resource, location: after_resetting_password_path_for(resource)
      else
        set_minimum_password_length
        respond_with resource
      end
    end

    protected

    def configure_permitted_parameters
      devise_parameter_sanitizer.permit(:reset_password, keys: [:email])
    end

    def after_resetting_password_path_for(_resource)
      root_path
    end
  end
end
