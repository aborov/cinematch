class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :verify_authenticity_token, only: [:google_oauth2, :facebook, :twitter, :apple]

  def google_oauth2
    @user = User.from_omniauth(request.env['omniauth.auth'])

    if @user.persisted?
      flash[:notice] = I18n.t 'devise.omniauth_callbacks.success', kind: 'Google'
      sign_in_and_redirect @user, event: :authentication
    else
      session['devise.google_data'] = request.env['omniauth.auth'].except('extra')
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  end

  def facebook
    handle_auth('Facebook')
  end

  def twitter
    handle_auth("Twitter")
  end

  def apple
    handle_auth("Apple")
  end

  def failure
    Rails.logger.error "OmniAuth failure: #{failure_message}"
    redirect_to new_user_session_path, alert: "Authentication failed: #{failure_message}"
  end

  private

  def handle_auth(kind)
    @user = User.from_omniauth(request.env["omniauth.auth"])
    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
    else
      Rails.logger.error("Failed to persist user from #{kind} OAuth: #{@user.errors.full_messages}")
      session["devise.#{kind.downcase}_data"] = request.env["omniauth.auth"].except(:extra)
      redirect_to new_user_registration_url, alert: "Failed to sign in with #{kind}. #{@user.errors.full_messages.join(", ")}"
    end
  end

  def failure_message
    exception = request.env["omniauth.error"]
    error = exception.error_reason if exception.respond_to?(:error_reason)
    error ||= exception.error if exception.respond_to?(:error)
    error ||= exception.message if exception.respond_to?(:message)
    error ||= "Authentication failed"
    error
  end

  def after_omniauth_failure_path_for(scope)
    Rails.logger.error("OmniAuth failure: #{failure_message}")
    Rails.logger.error("OmniAuth error: #{request.env['omniauth.error'].inspect}")
    super(scope)
  end
end
