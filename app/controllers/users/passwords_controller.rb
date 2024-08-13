class Users::PasswordsController < Devise::PasswordsController
  def update
    super do |resource|
      if resource.errors.empty?
        sign_in(resource, bypass: true)
        flash[:notice] = "Your password has been changed successfully."
      end
    end
  end

  protected

  def after_resetting_password_path_for(resource)
    root_path # or any other path you want to redirect to after password reset
  end
end