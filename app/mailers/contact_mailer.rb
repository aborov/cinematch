class ContactMailer < ApplicationMailer
  default to: 'info@cinematch.net'

  def contact_email(name, email, subject, message)
    @name = name
    @email = email
    @subject = subject
    @message = message
    mail(from: "Cinematch <info@cinematch.net>", reply_to: email, subject: "Cinematch Contact: #{subject}")
  end
end
