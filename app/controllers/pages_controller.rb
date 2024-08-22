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

    if verify_recaptcha(model: @contact)
      if @contact.name.present? && @contact.email.present? && @contact.subject.present? && @contact.message.present?
        ContactMailer.contact_email(@contact.name, @contact.email, @contact.subject, @contact.message).deliver_now
        redirect_to contact_path, notice: 'Your message has been sent. We will get back to you soon!'
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
    params.require(:contact).permit(:name, :email, :subject, :message)
  end
end
