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
          ContactMailer.contact_email(
            @contact.name, 
            @contact.email, 
            @contact.subject, 
            @contact.message,
            params.dig(:contact, :attachment)
          ).deliver_now
          redirect_to contact_path, notice: 'Your message has been sent. We will get back to you soon!'
        rescue SecurityError
          flash.now[:alert] = 'File upload failed security check. Please try again with a different file.'
          render :contact
        rescue StandardError => e
          Rails.logger.error "Contact email error: #{e.message}"
          flash.now[:alert] = 'An error occurred while sending your message. Please try again.'
          render :contact
        end
      else
        flash.now[:alert] = 'Please fill in all fields.'
        render :contact
      end
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

  private

  def contact_params
    params.require(:contact).permit(:name, :email, :subject, :message, :attachment)
  end
end
