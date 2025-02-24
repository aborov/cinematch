# frozen_string_literal: true

class PagesController < ApplicationController
  layout 'landing', only: [:landing]

  def landing
    return unless user_signed_in?

    redirect_to recommendations_path
  end

  def contact
    @contact = if user_signed_in?
      OpenStruct.new(name: current_user.name, email: current_user.email)
    else
      OpenStruct.new
    end
  end

  def send_contact_email
    @contact = OpenStruct.new(contact_params)

    if !user_signed_in? && @contact.subject == 'Age Verification'
      redirect_to new_user_session_path, alert: 'Please sign in to submit age verification documents.'
      return
    end

    # Only verify recaptcha in production
    if !Rails.env.production? || verify_recaptcha(model: @contact)
      if @contact.name.present? && @contact.email.present? && @contact.subject.present? && @contact.message.present?
        begin
          attachment_data = if params.dig(:contact, :attachment).present?
            file = params[:contact][:attachment]
            {
              filename: file.original_filename,
              content: Base64.strict_encode64(File.read(file.tempfile)),
              content_type: file.content_type
            }
          end

          ContactMailer.contact_email(
            @contact.name, 
            @contact.email, 
            @contact.subject, 
            @contact.message,
            attachment_data
          ).deliver_later

          redirect_to contact_path, notice: 'Your message has been sent. We will get back to you soon!'
          return
        rescue SecurityError
          flash.now[:alert] = 'File upload failed security check. Please try again with a different file.'
        rescue StandardError => e
          Rails.logger.error "Contact email error: #{e.full_message}"
          flash.now[:alert] = 'An error occurred while sending your message. Please try again.'
        end
      else
        flash.now[:alert] = 'Please fill in all fields.'
      end
      render :contact
    else
      flash.now[:alert] = 'reCAPTCHA verification failed. Please try again.'
      render :contact
    end
  end

  def privacy
  end

  def terms
  end

  def data_deletion
  end

  def about
    @app_version = Rails.application.config.version
    @changelog = Rails.application.config.changelog rescue []
  end

  private

  def contact_params
    params.require(:contact).permit(:name, :email, :subject, :message, :attachment)
  end
end
