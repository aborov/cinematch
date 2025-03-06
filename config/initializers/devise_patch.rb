# https://github.com/heartcombo/devise/issues/5644
# Skip setting the secret key during asset precompilation
unless ($PROGRAM_NAME.include?('assets:precompile') || ARGV.include?('assets:precompile'))
  Devise.setup do |config|
    config.secret_key = Rails.application.secret_key_base
  end
end
