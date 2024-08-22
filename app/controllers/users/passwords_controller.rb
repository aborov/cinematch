# frozen_string_literal: true

module Users
  class PasswordsController < Devise::PasswordsController
    def create
      if verify_recaptcha
        super
      else
        self.resource = resource_class.new
        flash.now[:alert] = 'reCAPTCHA verification failed, please try again.'
        respond_with_navigational(resource) { render :new }
      end
    end

    def update
      super do |resource|
        if resource.errors.empty?
          sign_in(resource, bypass: true)
          flash[:notice] = 'Your password has been changed successfully.'
        end
      end
    end

    protected

    def after_resetting_password_path_for(_resource)
      root_path # or any other path you want to redirect to after password reset
    end
  end
end
