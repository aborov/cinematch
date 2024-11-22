class ContactMailer < ApplicationMailer
  default to: 'info@cinematch.net'
  include Rails.application.routes.url_helpers

  def contact_email(name, email, subject, message, attachment = nil)
    @name = name
    @email = email
    @subject = subject
    @message = message
    
    if attachment.present?
      begin
        secure_attachment = FileSecurityService.validate_and_sanitize(attachment)
        attachments[secure_attachment.original_filename] = {
          content: secure_attachment.read,
          content_type: secure_attachment.content_type
        }
      rescue FileSecurityService::FileSecurityError => e
        Rails.logger.error "File security error: #{e.message}"
        raise
      rescue StandardError => e
        Rails.logger.error "Attachment processing error: #{e.message}"
        raise SecurityError, "File processing failed"
      end
    end
    
    mail(
      from: "Cinematch <info@cinematch.net>", 
      reply_to: email, 
      subject: "Cinematch Contact: #{subject}"
    )
  end

  def underage_warning(user)
    @user = user
    @profile_url = profile_url(host: Rails.application.config.action_mailer.default_url_options[:host],
                             protocol: Rails.application.config.action_mailer.default_url_options[:protocol] || 'http')
    @contact_url = contact_url(
      'contact[subject]': 'Age Verification',
      host: Rails.application.config.action_mailer.default_url_options[:host],
      protocol: Rails.application.config.action_mailer.default_url_options[:protocol] || 'http'
    )
    
    mail(
      to: user.email,
      subject: "Important Notice: Age Requirement for Your Cinematch Account",
      template_name: 'underage_warning'
    )
  end
end
