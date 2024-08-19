# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'info@cinematch.net'
  layout 'mailer'
end
