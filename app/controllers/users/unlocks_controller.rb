class Users::UnlocksController < Devise::UnlocksController
  prepend_before_action :check_captcha, only: [:create]

  protected

  def after_unlock_path_for(resource)
    root_path
  end

  private

  def check_captcha
    return if verify_recaptcha

    self.resource = resource_class.new
    resource.validate
    respond_with_navigational(resource) { render :new }
  end
end
