class Users::SessionsController < Devise::SessionsController
  prepend_before_action :check_user_confirmation, only: [:create]
  skip_before_action :verify_authenticity_token, only: :create
  
  def new
    Rails.logger.info "=== Starting Sessions#new ==="
    super
  end

  protected

  def check_user_confirmation
    Rails.logger.warn "=== Checking user confirmation ==="
    user = User.find_by(email: sign_in_params[:email])
    Rails.logger.warn "Found user: #{user&.id}, Confirmed: #{user&.confirmed?}, Confirmation sent at: #{user&.confirmation_sent_at}"
    
    if user && !user.confirmed?
      Rails.logger.warn "User #{user.id} is unconfirmed, sending instructions"
      begin
        # Always resend confirmation instructions - Devise will handle token generation/expiry
        user.send_confirmation_instructions
        Rails.logger.warn "Confirmation instructions sent synchronously"
      rescue => e
        Rails.logger.error "Error sending confirmation: #{e.full_message}"
      end
      flash[:notice] = t('devise.confirmations.send_instructions')
      redirect_to new_user_session_path
      return false
    end
  end

  def auth_options
    { scope: resource_name, recall: "#{controller_path}#new" }
  end
end
