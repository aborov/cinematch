# frozen_string_literal: true

# == Schema Information
#
# Table name: user_preferences
#
#  id                          :bigint           not null, primary key
#  ai_model                    :string
#  basic_survey_completed      :boolean          default(FALSE)
#  deleted_at                  :datetime
#  disable_adult_content       :boolean
#  extended_survey_completed   :boolean          default(FALSE)
#  extended_survey_in_progress :boolean          default(FALSE)
#  favorite_genres             :json
#  personality_profiles        :json
#  personality_summary         :text
#  use_ai                      :boolean          default(FALSE)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  user_id                     :bigint           not null
#
# Indexes
#
#  index_user_preferences_on_deleted_at  (deleted_at)
#  index_user_preferences_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserPreference < ApplicationRecord
  acts_as_paranoid
  belongs_to :user, required: true

  GENRE_MAPPING = {
    openness: %w[Science-Fiction Fantasy Animation],
    conscientiousness: %w[Drama Biography History],
    extraversion: %w[Comedy Action Adventure],
    agreeableness: %w[Romance Family Music],
    neuroticism: %w[Thriller Mystery Horror]
  }.freeze

  validates :ai_model, inclusion: { 
    in: AiModelsConfig::MODELS.keys,
    allow_nil: true 
  }

  def calculate_match_score(genre_ids)
    genre_names = Genre.where(tmdb_id: genre_ids).pluck(:name)
    
    # Start with base scores
    big_five_score = calculate_big_five_score(genre_names)
    favorite_genres_score = calculate_favorite_genres_score(genre_names)
    
    # Initialize additional scores from extended profile
    extended_scores = {}
    
    # Get the full personality profile
    profile = personality_profiles
    
    # Calculate weights based on profile depth
    weights = determine_score_weights(profile)
    
    # Include extended trait scores if available
    if profile[:extended_traits].present?
      # HEXACO score - focus on honesty-humility trait for ethical/moral content
      extended_scores[:hexaco] = calculate_hexaco_genre_match(genre_names, profile[:extended_traits][:hexaco])
      
      # Attachment style score - impacts emotional/relationship content preferences
      extended_scores[:attachment] = calculate_attachment_genre_match(genre_names, profile[:extended_traits][:attachment_style])
      
      # Moral foundations - impacts theme preferences
      if profile[:extended_traits][:moral_foundations].present?
        extended_scores[:moral] = calculate_moral_foundations_match(genre_names, profile[:extended_traits][:moral_foundations])
      end
      
      # Cognitive style - impacts complexity and narrative structure preferences
      if profile[:extended_traits][:cognitive].present?
        extended_scores[:cognitive] = calculate_cognitive_match(genre_names, profile[:extended_traits][:cognitive])
      end
    end
    
    # Calculate emotional intelligence impact - affects emotional content
    extended_scores[:emotional_intelligence] = calculate_emotional_intelligence_match(
      genre_names, 
      profile[:emotional_intelligence]
    )
    
    # Combine all scores using weighted approach
    final_score = 0
    final_score += (big_five_score * weights[:big_five])
    final_score += (favorite_genres_score * weights[:favorite_genres])
    
    # Add extended scores if available
    extended_scores.each do |key, score|
      if score > 0 && weights[key].present?
        final_score += (score * weights[key])
      end
    end
    
    # Normalize to ensure we stay in 0-100 range
    [final_score, 100].min
  end

  def personality_profiles
    profiles = read_attribute(:personality_profiles)
    return {} if profiles.nil?
    
    # Handle string representation (which might happen with some ActiveRecord operations)
    profiles = JSON.parse(profiles) if profiles.is_a?(String)
    
    # Ensure we return a hash with symbolized keys
    profiles.is_a?(Hash) ? profiles.deep_symbolize_keys : {}
  end

  def favorite_genres
    read_attribute(:favorite_genres) || []
  end

  def self.ransackable_attributes(auth_object = nil)
    [
      "id", 
      "user_id", 
      "favorite_genres", 
      "personality_profiles", 
      "disable_adult_content",
      "use_ai",
      "ai_model",
      "created_at", 
      "updated_at"
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user"]
  end
  
  def recommendations_outdated?
    # Delegate to user_recommendation if it exists
    if user&.user_recommendation.present?
      user.user_recommendation.recommendations_outdated?
    else
      true # If there's no recommendation object, consider recommendations outdated
    end
  end

  def ai_model
    read_attribute(:ai_model) || AiModelsConfig.default_model
  end

  def ensure_recommendations
    # Create user_recommendation if it doesn't exist
    user_rec = user.ensure_user_recommendation
    
    # Delegate to the user_recommendation object
    user_rec.ensure_recommendations
  end

  private

  def calculate_big_five_score(genres)
    score = 0
    profiles = personality_profiles
    
    # Extract big_five from the profile structure
    big_five = if profiles.is_a?(Hash)
      if profiles.key?(:big_five)
        profiles[:big_five]
      elsif profiles.key?('big_five')
        profiles['big_five']
      else
        profiles
      end
    else
      {}
    end
    
    Rails.logger.info("Calculating big five score with profiles: #{big_five.inspect}")
    Rails.logger.info("Genres: #{genres.inspect}")
    
    GENRE_MAPPING.each do |trait, trait_genres|
      trait_str = trait.to_s
      trait_sym = trait.to_sym
      
      # Try both symbol and string keys
      trait_score = big_five[trait_sym].to_f
      trait_score = big_five[trait_str].to_f if trait_score == 0 && big_five.key?(trait_str)
      
      match = (genres & trait_genres).size
      
      Rails.logger.info("Trait: #{trait_str}, Score: #{trait_score}, Matching genres: #{match}")
      
      score += trait_score * match
    end
    
    Rails.logger.info("Final big five score: #{score}")
    score
  end

  def calculate_favorite_genres_score(genres)
    user_favorite_genres = favorite_genres.is_a?(String) ? favorite_genres.split(',').map(&:strip) : favorite_genres
    
    Rails.logger.info("Calculating favorite genres score")
    Rails.logger.info("User favorite genres: #{user_favorite_genres.inspect}")
    Rails.logger.info("Content genres: #{genres.inspect}")
    
    if user_favorite_genres.empty?
      Rails.logger.warn("User has no favorite genres")
      return 0
    end

    matching_genres = genres & user_favorite_genres
    score = matching_genres.size.to_f / user_favorite_genres.size
    
    Rails.logger.info("Matching genres: #{matching_genres.inspect}")
    Rails.logger.info("Score: #{score}")
    
    score
  end

  def determine_score_weights(profile)
    # Default weights for basic profile
    weights = {
      big_five: 0.5,
      favorite_genres: 0.4,
      emotional_intelligence: 0.1
    }
    
    # Adjust weights if we have extended profile data
    if profile[:extended_traits].present? && profile[:extended_traits][:profile_depth] == "extended"
      weights = {
        big_five: 0.3,
        favorite_genres: 0.3,
        emotional_intelligence: 0.1,
        hexaco: 0.1,
        attachment: 0.1,
        moral: 0.05,
        cognitive: 0.05
      }
    end
    
    weights
  end
  
  def calculate_hexaco_genre_match(genres, hexaco_data)
    return 0 unless hexaco_data.present?
    
    honesty_score = hexaco_data[:honesty_humility][:overall].to_f
    integrity_level = hexaco_data[:integrity_level]
    
    score = 0
    
    # High honesty individuals may prefer content with moral messages
    # Lower honesty individuals may enjoy morally ambiguous content
    moral_genres = ['Drama', 'Biography', 'History', 'War', 'Documentary']
    ambiguous_genres = ['Crime', 'Thriller', 'Mystery']
    
    if integrity_level == "highly_principled" || integrity_level == "principled"
      score += 25 if (genres & moral_genres).any?
    elsif integrity_level == "pragmatic" || integrity_level == "opportunistic"
      score += 25 if (genres & ambiguous_genres).any?
    end
    
    score
  end
  
  def calculate_attachment_genre_match(genres, attachment_data)
    return 0 unless attachment_data.present?
    
    attachment_style = attachment_data[:attachment_style]
    
    score = 0
    romantic_genres = ['Romance', 'Drama']
    action_genres = ['Action', 'Adventure', 'Thriller']
    complex_genres = ['Drama', 'Mystery', 'Science-Fiction']
    
    case attachment_style
    when "anxious"
      score += 25 if (genres & romantic_genres).any?
    when "avoidant"
      score += 25 if (genres & action_genres).any?
    when "fearful_avoidant"
      score += 25 if (genres & complex_genres).any?
    when "secure"
      score += 15 # Secure individuals enjoy diverse content
    end
    
    score
  end
  
  def calculate_moral_foundations_match(genres, moral_data)
    return 0 unless moral_data.present?
    
    moral_orientation = moral_data[:moral_orientation]
    
    score = 0
    progressive_genres = ['Documentary', 'Drama', 'Biography']
    traditional_genres = ['War', 'History', 'Western', 'Family']
    
    case moral_orientation
    when "progressive"
      score += 20 if (genres & progressive_genres).any?
    when "traditional"
      score += 20 if (genres & traditional_genres).any?
    when "moderate"
      score += 10 # Moderates have balanced preferences
    end
    
    score
  end
  
  def calculate_cognitive_match(genres, cognitive_data)
    return 0 unless cognitive_data.present?
    
    # Get cognitive style preferences
    visual_verbal = cognitive_data[:visual_verbal][:score]
    systematic_intuitive = cognitive_data[:systematic_intuitive][:score]
    abstract_concrete = cognitive_data[:abstract_concrete][:score]
    
    score = 0
    
    # Visual preference matches visually-driven genres
    if visual_verbal < -20 # Visual preference
      score += 15 if (genres & ['Action', 'Adventure', 'Animation', 'Fantasy']).any?
    end
    
    # Systematic preference matches structured genres
    if systematic_intuitive < -20 # Systematic preference
      score += 15 if (genres & ['Mystery', 'Crime', 'Thriller']).any?
    end
    
    # Abstract preference matches conceptual genres
    if abstract_concrete < -20 # Abstract preference
      score += 15 if (genres & ['Science-Fiction', 'Fantasy', 'Animation']).any?
    end
    
    score
  end
  
  def calculate_emotional_intelligence_match(genres, ei_data)
    return 0 unless ei_data.present?
    
    ei_level = ei_data[:ei_level]
    composite_score = ei_data[:composite_score].to_f
    
    score = 0
    emotional_genres = ['Drama', 'Romance', 'Family']
    complex_emotional_genres = ['Drama', 'Thriller', 'Mystery']
    
    case ei_level
    when "exceptional", "strong"
      score += 20 if (genres & complex_emotional_genres).any?
    when "moderate"
      score += 15 if (genres & emotional_genres).any?
    when "developing"
      score += 10 if (genres & ['Comedy', 'Action', 'Adventure']).any?
    end
    
    score
  end
end
