ActiveAdmin.register UserPreference do
  permit_params :user_id, :favorite_genres, :personality_profiles

  index do
    selectable_column
    id_column
    column :user
    column :favorite_genres
    column :personality_profiles
    column :created_at
    column :updated_at
    actions
  end

  index download_links: [:csv, :xml, :json, :pdf]

  filter :user
  filter :favorite_genres
  filter :personality_profiles
  filter :created_at
  filter :updated_at

  form do |f|
    f.inputs do
      f.input :user
      f.input :favorite_genres
      f.input :personality_profiles
    end
    f.actions
  end

  show do
    attributes_table do
      row :id
      row :user
      row :favorite_genres
      row :personality_profiles
      row :created_at
      row :updated_at
    end
  end

  controller do
    def index
      super do |format|
        format.pdf do
          user_preferences = UserPreference.ransack(params[:q]).result
          pdf = UserPreferencePdf.new(user_preferences)
          send_data pdf.render, filename: 'user_preferences.pdf', type: 'application/pdf', disposition: 'inline'
        end
      end
    end
  end
end
