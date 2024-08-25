# frozen_string_literal: true

module Users
  class PasswordsController < Devise::PasswordsController
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
      root_path
    end
  end
end
