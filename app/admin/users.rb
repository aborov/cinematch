# frozen_string_literal: true

ActiveAdmin.register User do
  permit_params :email, :password, :password_confirmation, :name, :dob, :gender, :admin

  index do
    selectable_column
    id_column
    column :name
    column :email
    column :gender
    column :dob
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
      f.input :password
      f.input :password_confirmation
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
    def index
      index! do |format|
        format.html
        format.csv { send_data collection.to_csv }
        format.pdf do
          pdf = UserPdf.new(collection)
          send_data pdf.render, filename: 'users.pdf', type: 'application/pdf', disposition: 'inline'
        end
      end
    end
  end

  # Define collection to be used in index
  def self.ransackable_attributes(auth_object = nil)
    ["admin", "created_at", "dob", "email", "gender", "id", "name", "provider", "uid"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user_preference", "survey_responses"]
  end
end
