# frozen_string_literal: true

class PagesController < ApplicationController
  layout 'landing', only: [:landing]

  def landing
    return unless user_signed_in?

    redirect_to recommendations_path
  end

  def contact
    @contact = OpenStruct.new(params[:contact])
  end

  def send_contact_email
    @contact = OpenStruct.new(contact_params)

    if verify_recaptcha(model: @contact)
      if @contact.name.present? && @contact.email.present? && @contact.subject.present? && @contact.message.present?
        ContactMailer.contact_email(@contact.name, @contact.email, @contact.subject, @contact.message).deliver_now
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

  private

  def contact_params
    params.require(:contact).permit(:name, :email, :subject, :message)
  end
end
