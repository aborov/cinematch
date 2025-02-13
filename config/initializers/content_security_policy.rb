# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https, "'unsafe-inline'", "'unsafe-eval'"
    policy.style_src   :self, :https, "'unsafe-inline'"
    policy.connect_src :self
    policy.frame_src   :self
    policy.frame_ancestors :none
    policy.form_action :self
    policy.base_uri    :self
  end

  # Comment out nonce configuration
  # config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  # config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Enable CSP reporting
  config.content_security_policy_report_only = true
end
