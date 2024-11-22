class ContactMailer < ApplicationMailer
  default to: 'info@cinematch.net'
  include Rails.application.routes.url_helpers

  def contact_email(name, email, subject, message, attachment = nil)
    @name = name
    @email = email
    @subject = subject
    @message = message
    
    if attachment && attachment.content_type.in?(['image/jpeg', 'image/png', 'application/pdf'])
      begin
        # Skip virus scan in development
        if Rails.env.production?
          scan_result = ClamAV.instance.scan_file(attachment.tempfile.path)
          raise SecurityError, "File failed security scan" unless scan_result.clean?
        end
        
        attachments[attachment.original_filename] = {
          mime_type: attachment.content_type,
          content: attachment.read
        }
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
