class Users::ConfirmationsController < Devise::ConfirmationsController
  def new
    super
  end

  def create
    self.resource = resource_class.find_by_email(params[:user][:email])
    
    if resource.nil?
      flash[:alert] = "Email address not found"
      redirect_to new_user_confirmation_path
      return
    end

    if resource.confirmed?
      flash[:notice] = "Email was already confirmed, please try signing in"
      redirect_to new_user_session_path
    else
      resource.resend_confirmation_instructions
      flash[:notice] = "Confirmation instructions have been sent to your email"
      redirect_to edit_user_registration_path
    end
  end

  protected

  def after_confirmation_path_for(resource_name, resource)
    sign_in(resource)
    surveys_path(type: 'basic')
  end
end 
