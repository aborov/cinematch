ActiveAdmin.register UserRecommendation do
  menu priority: 5, label: "User Recommendations"
  
  permit_params :user_id, :processing

  actions :all, except: [:destroy, :new, :create]  # Don't allow creating new recommendations manually

  index do
    selectable_column
    id_column
    column :user
    column :processing
    column :recommendations do |rec|
      if rec.content_ids_present? && !rec.empty_content_ids?
        if rec.recommended_content_ids.is_a?(Hash)
          movie_count = rec.recommended_content_ids["movies"]&.size || 0
          show_count = rec.recommended_content_ids["shows"]&.size || 0
          div do
            if movie_count > 0
              status_tag("#{movie_count} Movies")
            else
              span "#{movie_count} Movies"
            end
          end
          div do 
            if show_count > 0
              status_tag("#{show_count} Shows")
            else
              span "#{show_count} Shows"
            end
          end
          div "Total: #{rec.total_recommendations_count}"
        else
          "#{rec.total_recommendations_count} items"
        end
      else
        span "No Recommendations"
      end
    end
    column :recommendations_generated_at
    column :outdated do |rec|
      if rec.recommendations_outdated?
        status_tag("Outdated")
      else
        status_tag("Current")
      end
    end
    column :updated_at
    actions
  end

  filter :user
  filter :processing
  filter :recommendations_generated_at
  filter :created_at
  filter :updated_at

  action_item :regenerate, only: :show do
    link_to 'Regenerate Recommendations', regenerate_admin_user_recommendation_path(resource), method: :post
  end

  action_item :view_user_preference, only: :show do
    link_to 'View User Preference', admin_user_preference_path(resource.user.user_preference) if resource.user.user_preference.present?
  end

  member_action :regenerate, method: :post do
    recommendation = UserRecommendation.find(params[:id])
    recommendation.mark_as_outdated!
    recommendation.ensure_recommendations
    redirect_to admin_user_recommendation_path(recommendation), notice: "Recommendations regeneration has been queued"
  end

  show do
    attributes_table do
      row :id
      row :user
      row :processing do |rec|
        if rec.processing?
          status_tag("Processing")
        else
          status_tag("Idle")
        end
      end
      row :recommendations_generated_at
      row :age do |rec|
        if rec.recommendations_generated_at.present?
          time_ago = distance_of_time_in_words(rec.recommendations_generated_at, Time.current)
          if (Time.current - rec.recommendations_generated_at) > 7.days
            span "#{time_ago} ago (old)"
          elsif (Time.current - rec.recommendations_generated_at) > 3.days
            span "#{time_ago} ago"
          else
            status_tag("#{time_ago} ago")
          end
        else
          span "Never Generated"
        end
      end
      row :created_at
      row :updated_at
    end
    
    if resource.content_ids_present? && !resource.empty_content_ids?
      tabs do
        tab "Recommendations Overview" do
          panel "Recommendation Stats" do
            columns do
              column do
                attributes_table_for resource do
                  row "Total Recommendations" do |rec|
                    rec.total_recommendations_count
                  end
                  
                  if resource.recommended_content_ids.is_a?(Hash)
                    row "Movies" do |rec|
                      (rec.recommended_content_ids["movies"] || []).size
                    end
                    row "Shows" do |rec|
                      (rec.recommended_content_ids["shows"] || []).size
                    end
                  end
                end
              end
              
              column do
                content_types = {}
                
                if resource.content_ids_present? && !resource.empty_content_ids?
                  content_ids = resource.get_all_content_ids
                  
                  if content_ids.any?
                    # Get genre distribution
                    genres = Content.where(id: content_ids).joins(:genres)
                                     .group('genres.name').count
                                     
                    # Get content type distribution
                    content_types = Content.where(id: content_ids)
                                          .group(:content_type).count
                  end
                end
                
                if content_types.any?
                  h3 "Content Type Distribution"
                  render partial: 'admin/pie_chart', locals: { data: content_types }
                end
                
                if defined?(genres) && genres.any?
                  h3 "Top Genres"
                  render partial: 'admin/pie_chart', locals: { data: genres.sort_by { |_, v| -v }.first(10).to_h }
                end
              end
            end
          end
        end
        
        tab "Recommended Content" do
          panel "Content List" do
            if resource.content_ids_present? && !resource.empty_content_ids?
              content_ids = resource.get_all_content_ids
              
              if content_ids.any?
                paginated_content_ids = content_ids.first(20)  # Limit to 20 per page
                
                table_for Content.where(id: paginated_content_ids) do
                  column :id
                  column :title
                  column :content_type
                  column :release_year
                  column :score do |content|
                    if resource.recommendation_scores.present? && resource.recommendation_scores[content.id.to_s].present?
                      score = resource.recommendation_scores[content.id.to_s].to_f
                      div style: "width: 100px" do
                        div style: "background: #eee; width: 100%; height: 15px; border-radius: 4px;" do
                          div style: "background: #4CAF50; width: #{score * 100}%; height: 15px; border-radius: 4px;"
                        end
                      end
                      span "#{(score * 100).round}%"
                    end
                  end
                  column :genres do |content|
                    content.genres.pluck(:name).join(", ")
                  end
                  column :reason do |content|
                    if resource.recommendation_reasons.present? && resource.recommendation_reasons[content.id.to_s].present?
                      content_tag :div, class: 'recommendation-reason' do
                        resource.recommendation_reasons[content.id.to_s]
                      end
                    end
                  end
                  column :actions do |content|
                    link_to "View Content", admin_content_path(content)
                  end
                end
                
                div "Showing #{paginated_content_ids.size} of #{content_ids.size} recommendations"
              else
                div "No content IDs available"
              end
            else
              div "No recommendations"
            end
          end
        end
        
        tab "Genre Analysis" do
          panel "Genre Distribution" do
            if resource.content_ids_present? && !resource.empty_content_ids?
              content_ids = resource.get_all_content_ids
              
              if content_ids.any?
                # Get genre distribution
                genres = Content.where(id: content_ids).joins(:genres)
                                .group('genres.name').count
                                
                if genres.any?
                  table_for genres.sort_by { |k, v| -v }.first(15) do
                    column "Genre" do |genre_pair|
                      genre_pair[0]
                    end
                    column "Count" do |genre_pair|
                      genre_pair[1]
                    end
                    column "Percentage" do |genre_pair|
                      percentage = (genre_pair[1].to_f / content_ids.size * 100).round(1)
                      div style: "width: 200px" do
                        div style: "background: #eee; width: 100%; height: 20px; border-radius: 4px;" do
                          div style: "background: #2196F3; width: #{percentage}%; height: 20px; border-radius: 4px;"
                        end
                      end
                      span "#{percentage}%"
                    end
                  end
                else
                  div "No genre data available"
                end
              else
                div "No content IDs available"
              end
            else
              div "No recommendations"
            end
          end
        end
        
        tab "Personality Correlation" do
          panel "Personality Profile Impact" do
            if resource.user.user_preference&.personality_profiles.present?
              personality = resource.user.user_preference.personality_profiles
              
              if personality[:big_five].present?
                h3 "Big Five Traits and Content Recommendations"
                
                big_five = personality[:big_five]
                
                table_for big_five.sort_by { |k, v| -v }.to_a do
                  column "Trait" do |trait_pair|
                    b trait_pair[0].to_s.humanize
                  end
                  column "Personality Score" do |trait_pair|
                    div style: "width: 150px" do
                      div style: "background: #eee; width: 100%; height: 20px; border-radius: 4px;" do
                        div style: "background: #4CAF50; width: #{trait_pair[1] * 100}%; height: 20px; border-radius: 4px;"
                      end
                    end
                    span "#{(trait_pair[1] * 100).round}%"
                  end
                  column "Expected Genres" do |trait_pair|
                    trait = trait_pair[0].to_s
                    case trait
                    when "openness"
                      "Science Fiction, Fantasy, Animation"
                    when "conscientiousness"
                      "Drama, Biography, History"
                    when "extraversion"
                      "Comedy, Action, Adventure"
                    when "agreeableness"
                      "Romance, Family, Music"
                    when "neuroticism"
                      "Thriller, Mystery, Horror"
                    else
                      "Unknown"
                    end
                  end
                end
              else
                div "No Big Five personality data available"
              end
            else
              div "No personality profile data available"
              div do
                link_to "View User Preference", admin_user_preference_path(resource.user.user_preference) if resource.user.user_preference.present?
              end
            end
          end
        end
      end
    else
      panel "No Recommendations Available" do
        div "This user does not have any recommendations yet"
        div "Click the 'Regenerate Recommendations' button to create new recommendations"
      end
    end
  end

  # Add ransackable definitions
  def self.ransackable_attributes(auth_object = nil)
    [
      "id", "user_id", "processing", "recommendations_generated_at", 
      "created_at", "updated_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end

  # Allow accessing recommendation fields in the dashboard
  controller do
    def find_resource
      scoped_collection.find(params[:id])
    end
    
    def scoped_collection
      super.includes(:user)
    end
  end
end 
