# frozen_string_literal: true

class PagesController < ApplicationController
  layout 'landing', only: [:landing]

  def landing
    return unless user_signed_in?

    redirect_to recommendations_path
  end

  def contact
  end

  def send_contact_email
    if verify_recaptcha(action: 'contact')
      name = params[:name]
      email = params[:email]
      subject = params[:subject]
      message = params[:message]

      if name.present? && email.present? && subject.present? && message.present?
        ContactMailer.contact_email(name, email, subject, message).deliver_now
        redirect_to root_path, notice: 'Your message has been sent. We will get back to you soon!'
      else
        flash.now[:alert] = 'Please fill in all fields.'
        render :contact
      end
    else
      flash.now[:alert] = 'reCAPTCHA verification failed. Please try again.'
      render :contact
    end
  end
end
