namespace :admin do
  desc "Create or update admin user"
  task create: :environment do
    email = ENV['ADMIN_EMAIL']
    password = ENV['ADMIN_PASSWORD']

    if email.blank? || password.blank?
      puts "Error: ADMIN_EMAIL and ADMIN_PASSWORD must be set"
      exit
    end

    user = User.find_or_initialize_by(email: email)
    user.name = "Admin"
    user.password = password
    user.password_confirmation = password
    user.admin = true

    if user.save
      puts "Admin user created or updated successfully"
    else
      puts "Error creating admin user: #{user.errors.full_messages.join(', ')}"
    end
  end
end
