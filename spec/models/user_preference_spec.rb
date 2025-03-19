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
require 'rails_helper'

RSpec.describe UserPreference, type: :model do
  describe "associations" do
    it { should belong_to(:user).required }
  end

  describe "validations" do
    it { should validate_inclusion_of(:ai_model).in_array(AiModelsConfig::MODELS.keys).allow_nil }
  end

  describe "#generate_recommendations" do
    let(:user) { create(:user) }
    let(:user_preference) { user.user_preference }
    let!(:content1) { create(:content, genre_ids: [28, 12]) } # Action, Adventure
    let!(:content2) { create(:content, genre_ids: [18, 36]) } # Drama, History
    let!(:content3) { create(:content, genre_ids: [35, 10751]) } # Comedy, Family
    let!(:genre_action) { create(:genre, tmdb_id: 28, name: 'Action') }
    let!(:genre_adventure) { create(:genre, tmdb_id: 12, name: 'Adventure') }
    let!(:genre_drama) { create(:genre, tmdb_id: 18, name: 'Drama') }
    let!(:genre_history) { create(:genre, tmdb_id: 36, name: 'History') }
    let!(:genre_comedy) { create(:genre, tmdb_id: 35, name: 'Comedy') }
    let!(:genre_family) { create(:genre, tmdb_id: 10751, name: 'Family') }

    before do
      # Set up personality profile with high extraversion (matches Action, Adventure)
      user_preference.update(
        personality_profiles: {
          big_five: {
            openness: 30,
            conscientiousness: 40,
            extraversion: 90, # High extraversion -> Action, Adventure
            agreeableness: 50,
            neuroticism: 20
          }
        },
        favorite_genres: ['Action', 'Comedy']
      )
    end

    context "with traditional recommendations" do
      before do
        user_preference.update(use_ai: false)
      end

      it "generates recommendations based on personality and favorite genres" do
        recommendations = user_preference.generate_recommendations
        
        # Action/Adventure content should be first due to high extraversion
        expect(recommendations.first).to eq(content1.id)
        
        # Comedy content should be included due to favorite genres
        expect(recommendations).to include(content3.id)
      end

      it "excludes adult content when specified" do
        adult_content = create(:content, genre_ids: [28], adult: true)
        user_preference.update(disable_adult_content: true)
        
        recommendations = user_preference.generate_recommendations
        expect(recommendations).not_to include(adult_content.id)
      end
    end

    context "with AI recommendations" do
      before do
        user_preference.update(use_ai: true, ai_model: AiModelsConfig.default_model)
        
        # Mock the AI recommendation service
        allow(AiRecommendationService).to receive(:generate_recommendations).and_return(
          [
            [content3.id, content1.id, content2.id], # Recommended IDs
            { # Reasons
              content3.id.to_s => "Matches comedy preference",
              content1.id.to_s => "Matches action preference",
              content2.id.to_s => "Diverse recommendation"
            },
            { # Scores
              content3.id.to_s => 95,
              content1.id.to_s => 85,
              content2.id.to_s => 70
            }
          ]
        )
      end

      it "uses the AI recommendation service" do
        expect(AiRecommendationService).to receive(:generate_recommendations).with(user_preference)
        user_preference.generate_recommendations
      end

      it "stores AI-generated recommendations, reasons, and scores" do
        user_preference.generate_recommendations
        
        expect(user_preference.recommended_content_ids).to eq([content3.id, content1.id, content2.id])
        expect(user_preference.recommendation_reasons[content3.id.to_s]).to eq("Matches comedy preference")
        expect(user_preference.recommendation_scores[content1.id.to_s]).to eq(85)
      end
    end

    context "with errors" do
      it "returns empty array and logs error if personality_profiles is blank" do
        user_preference.update(personality_profiles: nil)
        expect(Rails.logger).to receive(:error).at_least(:once)
        
        expect(user_preference.generate_recommendations).to eq([])
      end

      it "returns empty array and logs error if favorite_genres is blank" do
        user_preference.update(favorite_genres: nil)
        expect(Rails.logger).to receive(:error).at_least(:once)
        
        expect(user_preference.generate_recommendations).to eq([])
      end

      it "handles AI service errors gracefully" do
        user_preference.update(use_ai: true)
        allow(AiRecommendationService).to receive(:generate_recommendations).and_raise(StandardError.new("API error"))
        
        expect(Rails.logger).to receive(:error).at_least(:once)
        expect(user_preference.generate_recommendations).to eq([])
        expect(user_preference.processing).to eq(false) # Ensures processing flag is reset
      end
    end
  end

  describe "#calculate_match_score" do
    let(:user) { create(:user) }
    let(:user_preference) { user.user_preference }
    let!(:genre_action) { create(:genre, tmdb_id: 28, name: 'Action') }
    let!(:genre_comedy) { create(:genre, tmdb_id: 35, name: 'Comedy') }
    let!(:genre_drama) { create(:genre, tmdb_id: 18, name: 'Drama') }

    before do
      user_preference.update(
        personality_profiles: {
          big_five: {
            openness: 30,
            conscientiousness: 80, # High conscientiousness -> Drama
            extraversion: 90,      # High extraversion -> Action, Comedy
            agreeableness: 50,
            neuroticism: 20
          }
        },
        favorite_genres: ['Comedy', 'Drama']
      )
    end

    it "calculates higher scores for genres matching personality traits" do
      action_score = user_preference.calculate_match_score([28]) # Action
      drama_score = user_preference.calculate_match_score([18])  # Drama
      
      # Drama should score higher due to both personality (conscientiousness) and favorite genres
      expect(drama_score).to be > action_score
    end

    it "calculates higher scores for favorite genres" do
      comedy_score = user_preference.calculate_match_score([35]) # Comedy (favorite)
      action_score = user_preference.calculate_match_score([28]) # Action (not favorite)
      
      # Comedy should score higher as it's a favorite genre
      expect(comedy_score).to be > action_score
    end

    it "combines personality and favorite genre scores" do
      # Drama matches both conscientiousness and favorite genres
      drama_score = user_preference.calculate_match_score([18])
      
      # Action only matches extraversion
      action_score = user_preference.calculate_match_score([28])
      
      # Comedy matches both extraversion and favorite genres
      comedy_score = user_preference.calculate_match_score([35])
      
      expect(comedy_score).to be > action_score
      expect(drama_score).to be > action_score
    end
  end

  describe "#ai_model" do
    let(:user) { create(:user) }
    let(:user_preference) { user.user_preference }

    it "returns the configured AI model when set" do
      user_preference.update(ai_model: 'gemini-2-pro-exp')
      expect(user_preference.ai_model).to eq('gemini-2-pro-exp')
    end

    it "returns the default model when not set" do
      user_preference.update(ai_model: nil)
      expect(user_preference.ai_model).to eq(AiModelsConfig.default_model)
    end
  end
end 
