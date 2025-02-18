ActiveAdmin.register UserPreference do
  permit_params :user_id, :favorite_genres, :personality_profiles, :recommended_content_ids, 
                :recommendations_generated_at, :disable_adult_content, :ai_model, :use_ai

  index do
    selectable_column
    id_column
    column :user
    column :favorite_genres do |pref|
      truncate(pref.favorite_genres.join(", "), length: 50) if pref.favorite_genres.present?
    end
    column :recommendations_count do |pref|
      pref.recommended_content_ids&.size || 0
    end
    column :recommendations_generated_at
    column :disable_adult_content
    column :use_ai
    column :ai_model
    column :outdated do |pref|
      status_tag(pref.recommendations_outdated?)
    end
    column :updated_at
    actions
  end

  index download_links: [:csv, :xml, :json, :pdf]

  filter :user
  filter :recommendations_generated_at
  filter :disable_adult_content
  filter :ai_model
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
      row :favorite_genres do |pref|
        pref.favorite_genres.join(", ") if pref.favorite_genres.present?
      end
      row :personality_profiles do |pref|
        pre code: JSON.pretty_generate(pref.personality_profiles)
      end
      row :recommended_content_ids do |pref|
        if pref.recommended_content_ids.present?
          table_for Content.where(id: pref.recommended_content_ids.first(10)) do
            column :title
            column :content_type
            column :release_year
            column :reason do |content|
              if pref.recommendation_reasons.present? && pref.recommendation_reasons[content.id.to_s].present?
                content_tag :div, class: 'recommendation-reason' do
                  pref.recommendation_reasons[content.id.to_s]
                end
              end
            end
          end
          div "Showing 10 of #{pref.recommended_content_ids.size} recommendations"
        end
      end
      row :recommendations_generated_at
      row :disable_adult_content
      row :use_ai
      row :ai_model
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

  # Add ransackable definitions
  def self.ransackable_attributes(auth_object = nil)
    [
      "id", "user_id", "favorite_genres", "disable_adult_content", 
      "recommendations_generated_at", "ai_model", "created_at", "updated_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
end
