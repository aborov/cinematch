# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'Cinematch <info@cinematch.net>'
  layout 'mailer'
end
