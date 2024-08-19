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
    column :created_at
    actions
  end

  filter :name
  filter :email
  filter :gender
  filter :dob
  filter :admin
  filter :created_at

  form do |f|
    f.inputs do
      f.input :name
      f.input :email
      f.input :gender
      f.input :dob
      f.input :admin, as: :boolean
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end
end
