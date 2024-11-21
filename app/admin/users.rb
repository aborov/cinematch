# frozen_string_literal: true

ActiveAdmin.register User do
  permit_params :email, :password, :password_confirmation, :name, :dob, :gender, :admin

  scope :all
  scope :underage, -> { where("dob > ? AND dob IS NOT NULL", 13.years.ago.to_date) }
  scope :teenage, -> { where("dob > ? AND dob <= ? AND dob IS NOT NULL", 18.years.ago.to_date, 13.years.ago.to_date) }
  scope :adult, -> { where("dob <= ? AND dob IS NOT NULL", 18.years.ago.to_date) }
  scope :warned, -> { where.not(warning_sent_at: nil) }
  scope :not_warned, -> { underage.where(warning_sent_at: nil) }

  filter :dob_gt, label: 'Born after', as: :datepicker
  filter :dob_lt, label: 'Born before', as: :datepicker
  filter :warning_sent_at
  
  batch_action :send_warning_emails do |ids|
    sent_count = 0
    batch_action_collection.find(ids).each do |user|
      if user.underage?
        user.send_underage_warning_email
        sent_count += 1
      end
    end
    redirect_to collection_path, notice: "Warning emails have been sent to #{sent_count} underage users"
  end

  member_action :send_warning_email, method: :put do
    resource.send_underage_warning_email
    resource.reload
    redirect_to resource_path, notice: "Warning email sent at #{resource.warning_sent_at.strftime('%Y-%m-%d %H:%M:%S')}"
  end

  member_action :reset_warning, method: :put do
    resource.update_column(:warning_sent_at, nil)
    resource.reload
    redirect_to resource_path, notice: "Warning status has been reset"
  end

  action_item :send_warning_email, only: :show do
    if resource.underage?
      link_to 'Send Warning Email', send_warning_email_admin_user_path(resource), method: :put
    end
  end

  action_item :reset_warning, only: :show do
    if resource.warning_sent_at.present?
      link_to 'Reset Warning Status', reset_warning_admin_user_path(resource), 
              method: :put,
              data: { confirm: 'Are you sure? This will reset the warning status.' }
    end
  end

  index do
    selectable_column
    id_column
    column :name
    column :email
    column :gender
    column :dob
    column :age do |user|
      if user.dob
        age = ((Time.current - user.dob.to_time) / 1.year).floor
        status_tag(age, class: user.underage? ? 'error' : 'ok')
      else
        "Not set"
      end
    end
    column :warning_sent_at do |user|
      if user.warning_sent_at
        status_tag(user.warning_sent_at.strftime('%Y-%m-%d'), class: 'warning')
      end
    end
    column :admin
    column :provider
    column :created_at
    actions
  end

  index download_links: [:csv, :xml, :json, :pdf]

  filter :name
  filter :email
  filter :gender
  filter :dob
  filter :admin
  filter :provider
  filter :created_at

  form do |f|
    f.inputs do
      f.input :name
      f.input :email
      f.input :gender, as: :select, collection: ['Male', 'Female', 'Non-binary']
      f.input :dob, as: :datepicker
      f.input :admin, as: :boolean
      f.input :password, hint: "Leave blank if you don't want to change it"
      f.input :password_confirmation, hint: "Leave blank if you don't want to change it"
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :name
      row :email
      row :gender
      row :dob
      row :admin
      row :provider
      row :uid
      row :created_at
      row :updated_at
      row :warning_sent_at
      row :days_since_warning do |user|
        if user.warning_sent_at
          ((Time.current - user.warning_sent_at) / 1.day).floor
        end
      end
    end

    panel "User Preferences" do
      attributes_table_for user.user_preference do
        row :favorite_genres
        row :personality_profiles
      end
    end

    panel "Survey Responses" do
      table_for user.survey_responses do
        column :survey_question
        column :response
        column :created_at
      end
    end
  end

  controller do
    def action_methods
      super
    end

    def scoped_collection
      end_of_association_chain.includes(:user_preference, :survey_responses)
    end

    def update
      if params[:user][:password].blank? && params[:user][:password_confirmation].blank?
        params[:user].delete(:password)
        params[:user].delete(:password_confirmation)
      end
      super
    end
  end

  # Define collection to be used in index
  def self.ransackable_attributes(auth_object = nil)
    ["admin", "created_at", "dob", "email", "gender", "id", "name", "provider", "uid", "warning_sent_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user_preference", "survey_responses"]
  end

  # Add this to customize row styling
  index as: :table do |user|
    row_class = user.underage? ? 'underage' : ''
    tr(class: row_class)
  end

  sidebar "User Statistics", only: :index do
    div class: "user-stats" do
      h4 "Age Groups"
      ul do
        li "Under 13: #{User.underage.count}"
        li "13-18: #{User.teenage.count}"
        li "Over 18: #{User.adult.count}"
        li "No DOB set: #{User.where(dob: nil).count}"
      end

      h4 "Warning Status"
      ul do
        li "Warned: #{User.warned.count}"
        li "Underage Not Warned: #{User.not_warned.count}"
      end
    end
  end
end
