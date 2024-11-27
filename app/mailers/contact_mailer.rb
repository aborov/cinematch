class ContactMailer < ApplicationMailer
  default to: 'info@cinematch.net'
  include Rails.application.routes.url_helpers

  def contact_email(name, email, subject, message, attachment_data = nil)
    @name = name
    @email = email
    @subject = subject
    @message = message
    
    if attachment_data.present?
      begin
        # Decode the base64 content
        decoded_content = Base64.strict_decode64(attachment_data[:content])
        
        # Validate file size (5MB limit)
        if decoded_content.bytesize > 5.megabytes
          raise FileSecurityService::FileSecurityError, 'File size exceeds 5MB limit'
        end
        
        # Create a temporary file for security validation
        temp_file = Tempfile.new(['attachment', File.extname(attachment_data[:filename])])
        begin
          temp_file.binmode
          temp_file.write(decoded_content)
          temp_file.rewind
          
          # Create an uploaded file object for security validation
          uploaded_file = ActionDispatch::Http::UploadedFile.new(
            tempfile: temp_file,
            filename: attachment_data[:filename],
            type: attachment_data[:content_type]
          )
          
          # Run security validations
          secure_attachment = FileSecurityService.validate_and_sanitize(uploaded_file)
          
          # Add the validated attachment to the email
          attachments[secure_attachment.original_filename] = {
            mime_type: attachment_data[:content_type],
            content: decoded_content,
            encoding: 'binary'
          }
        ensure
          temp_file.close
          temp_file.unlink
        end
      rescue FileSecurityService::FileSecurityError => e
        Rails.logger.error "File security error: #{e.message}"
        raise
      rescue StandardError => e
        Rails.logger.error "Attachment processing error: #{e.full_message}"
        raise SecurityError, "File processing failed: #{e.message}"
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
    @profile_url = profile_url(
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
