ActiveAdmin.register UserPreference do
  permit_params :user_id, :favorite_genres, :personality_profiles, :personality_summary,
                :disable_adult_content, :ai_model, :use_ai

  index do
    selectable_column
    id_column
    column :user
    column :favorite_genres do |pref|
      truncate(pref.favorite_genres.join(", "), length: 50) if pref.favorite_genres.present?
    end
    column :personality_summary do |pref|
      truncate(pref.personality_summary, length: 50) if pref.personality_summary.present?
    end
    column :surveys do |pref|
      div do
        if pref.user.basic_survey_completed?
          status_tag("Basic")
        else
          span "Basic (incomplete)"
        end
      end
      div do 
        if pref.user.extended_survey_completed?
          status_tag("Extended")
        else
          span "Extended (incomplete)"
        end
      end
    end
    column :disable_adult_content
    column :use_ai
    column :ai_model
    column :updated_at
    actions
  end

  index download_links: [:csv, :xml, :json, :pdf]

  filter :user
  filter :disable_adult_content
  filter :use_ai
  filter :ai_model
  filter :created_at
  filter :updated_at

  form do |f|
    f.inputs do
      f.input :user
      f.input :favorite_genres
      f.input :personality_profiles
      f.input :personality_summary
      f.input :disable_adult_content
      f.input :use_ai
      f.input :ai_model, collection: AiModelsConfig::MODELS.keys
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
      row :personality_summary
      row :surveys do |pref|
        div do
          b "Basic Survey: "
          if pref.user.basic_survey_completed?
            status_tag("Completed")
          else
            span "Incomplete"
          end
          span "Progress: #{pref.user.basic_survey_progress}%" if pref.user.basic_survey_in_progress?
        end
        div do 
          b "Extended Survey: "
          if pref.user.extended_survey_completed?
            status_tag("Completed")
          else
            span "Incomplete"
          end
          span "Progress: #{pref.user.extended_survey_progress}%" if pref.user.extended_survey_in_progress?
        end
      end
    end
    
    panel "Personality Profile" do
      if pref.personality_profiles.present?
        tabs do
          tab "Big Five" do
            if pref.personality_profiles.dig(:big_five).present?
              table_for pref.personality_profiles[:big_five].to_a do
                column "Trait" do |trait_pair|
                  b trait_pair[0].to_s.humanize
                end
                column "Score" do |trait_pair|
                  div style: "width: 200px" do
                    div style: "background: #eee; width: 100%; height: 20px; border-radius: 4px;" do
                      div style: "background: #4CAF50; width: #{trait_pair[1] * 100}%; height: 20px; border-radius: 4px;"
                    end
                  end
                  span "#{(trait_pair[1] * 100).round}%"
                end
              end
            else
              div "No Big Five data available"
            end
          end
          
          tab "Emotional Intelligence" do
            if pref.personality_profiles.dig(:emotional_intelligence).present?
              table_for pref.personality_profiles[:emotional_intelligence].to_a do
                column "Trait" do |trait_pair|
                  b trait_pair[0].to_s.humanize
                end
                column "Score" do |trait_pair|
                  div style: "width: 200px" do
                    div style: "background: #eee; width: 100%; height: 20px; border-radius: 4px;" do
                      div style: "background: #2196F3; width: #{trait_pair[1] * 100}%; height: 20px; border-radius: 4px;"
                    end
                  end
                  span "#{(trait_pair[1] * 100).round}%"
                end
              end
            else
              div "No Emotional Intelligence data available"
            end
          end
          
          tab "Extended Traits" do
            if pref.personality_profiles.dig(:extended_traits).present?
              accordion do
                pref.personality_profiles[:extended_traits].each do |trait_category, traits|
                  panel trait_category.to_s.humanize do
                    table_for traits.to_a do
                      column "Trait" do |trait_pair|
                        b trait_pair[0].to_s.humanize
                      end
                      column "Score" do |trait_pair|
                        div style: "width: 200px" do
                          div style: "background: #eee; width: 100%; height: 20px; border-radius: 4px;" do
                            div style: "background: #FF9800; width: #{trait_pair[1] * 100}%; height: 20px; border-radius: 4px;"
                          end
                        end
                        span "#{(trait_pair[1] * 100).round}%"
                      end
                    end
                  end
                end
              end
            else
              div "No Extended Traits data available"
            end
          end
          
          tab "JSON Data" do
            pre code: JSON.pretty_generate(pref.personality_profiles) if pref.personality_profiles.present?
          end
        end
      else
        div "No personality profile data available"
      end
    end
    
    row :disable_adult_content
    row :use_ai
    row :ai_model
    row :created_at
    row :updated_at
    
    # Add a link to view the user's recommendations
    row :user_recommendations do |pref|
      if pref.user.user_recommendation.present?
        link_to "View Recommendations", admin_user_recommendation_path(pref.user.user_recommendation)
      else
        "No recommendations found"
      end
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
      "ai_model", "use_ai", "created_at", "updated_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
end
