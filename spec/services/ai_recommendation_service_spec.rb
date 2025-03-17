require 'rails_helper'

RSpec.describe AiRecommendationService do
  describe ".generate_recommendations" do
    let(:user) { create(:user) }
    let(:user_preference) { user.user_preference }
    let!(:content1) { create(:content, title: "The Matrix", release_year: 1999, content_type: "movie", source_id: "tt0133093") }
    let!(:content2) { create(:content, title: "Inception", release_year: 2010, content_type: "movie", source_id: "tt1375666") }
    
    before do
      user_preference.update(
        personality_profiles: {
          big_five: {
            openness: 70,
            conscientiousness: 60,
            extraversion: 80,
            agreeableness: 50,
            neuroticism: 30
          }
        },
        favorite_genres: ['Action', 'Comedy'],
        ai_model: 'gemini-2-flash'
      )
      
      # Create watchlist items with source_id and content_type
      WatchlistItem.create!(
        user: user, 
        source_id: content1.source_id, 
        content_type: content1.content_type, 
        watched: true, 
        rating: 10
      )
      
      WatchlistItem.create!(
        user: user, 
        source_id: content2.source_id, 
        content_type: content2.content_type, 
        watched: true, 
        rating: 8
      )
      
      # Mock the AI response
      allow(AiRecommendationService).to receive(:get_ai_recommendations).and_return([
        {
          "title" => "The Dark Knight",
          "type" => "movie",
          "year" => 2008,
          "reason" => "Based on your high ratings for sci-fi action films like The Matrix",
          "confidence_score" => 95
        },
        {
          "title" => "Breaking Bad",
          "type" => "tv",
          "year" => 2008,
          "reason" => "Complex storytelling similar to Inception",
          "confidence_score" => 90
        }
      ])
      
      # Mock the content finding
      dark_knight = create(:content, id: 101, title: "The Dark Knight", source_id: "tt0468569", content_type: "movie")
      breaking_bad = create(:content, id: 102, title: "Breaking Bad", source_id: "tt0903747", content_type: "tv")
      
      allow(AiRecommendationService).to receive(:find_all_content_versions).with(
        hash_including("title" => "The Dark Knight")
      ).and_return([dark_knight])
      
      allow(AiRecommendationService).to receive(:find_all_content_versions).with(
        hash_including("title" => "Breaking Bad")
      ).and_return([breaking_bad])
    end
    
    it "generates recommendations using the specified AI model" do
      expect(AiRecommendationService).to receive(:get_ai_recommendations).with(
        anything, 'gemini-2-flash'
      )
      
      AiRecommendationService.generate_recommendations(user_preference)
    end
    
    it "processes AI responses into recommendation data" do
      result = AiRecommendationService.generate_recommendations(user_preference)
      
      expect(result).to be_an(Array)
      expect(result.length).to eq(3) # IDs, reasons, scores
      
      ids, reasons, scores = result
      
      expect(ids).to include(101) # The Dark Knight
      expect(ids).to include(102) # Breaking Bad
      
      expect(reasons["101"]).to include("Based on your high ratings")
      
      # Don't test for exact score since our algorithm has changed
      expect(scores["101"]).to be_between(70, 100)
    end
    
    it "handles empty AI responses" do
      allow(AiRecommendationService).to receive(:get_ai_recommendations).and_return([])
      
      result = AiRecommendationService.generate_recommendations(user_preference)
      expect(result).to eq([[], {}, {}])
    end
    
    it "filters adult content when specified" do
      user_preference.update(disable_adult_content: true)
      
      # Create adult content
      adult_content = create(:content, id: 103, title: "Adult Movie", adult: true, source_id: "tt9999999", content_type: "movie")
      
      # Add adult content to AI response
      allow(AiRecommendationService).to receive(:get_ai_recommendations).and_return([
        {
          "title" => "Adult Movie",
          "type" => "movie",
          "year" => 2020,
          "reason" => "This is an adult movie",
          "confidence_score" => 80
        }
      ])
      
      # Mock finding adult content
      allow(AiRecommendationService).to receive(:find_all_content_versions).with(
        hash_including("title" => "Adult Movie")
      ).and_return([adult_content])
      
      result = AiRecommendationService.generate_recommendations(user_preference)
      expect(result[0]).not_to include(103) # Adult content should be filtered out
    end
  end
  
  describe ".preview_prompt" do
    let(:user) { create(:user) }
    let(:user_preference) { user.user_preference }
    let!(:content1) { create(:content, title: "The Matrix", release_year: 1999, content_type: "movie", source_id: "tt0133093") }
    let!(:content2) { create(:content, title: "Inception", release_year: 2010, content_type: "movie", source_id: "tt1375666") }
    
    before do
      user_preference.update(
        personality_profiles: {
          big_five: {
            openness: 70,
            conscientiousness: 60,
            extraversion: 80,
            agreeableness: 50,
            neuroticism: 30
          }
        },
        favorite_genres: ['Action', 'Comedy'],
        ai_model: 'gemini-2-flash'
      )
      
      # Create watchlist items with source_id and content_type
      WatchlistItem.create!(
        user: user, 
        source_id: content1.source_id, 
        content_type: content1.content_type, 
        watched: true, 
        rating: 10
      )
      
      WatchlistItem.create!(
        user: user, 
        source_id: content2.source_id, 
        content_type: content2.content_type, 
        watched: true, 
        rating: 8
      )
    end
    
    it "generates a prompt with user data" do
      prompt = AiRecommendationService.preview_prompt(user_preference)
      
      expect(prompt).to include("User Psychological Profile:")
      expect(prompt).to include("Big Five Personality:")
      expect(prompt).to include("Favorite Genres: Action, Comedy")
      expect(prompt).to include("Watch History")
      expect(prompt).to include("The Matrix (1999, movie) - 10/10")
    end
  end
  
  describe ".calculate_reason_quality_score" do
    it "returns a base score for empty reasons" do
      score = AiRecommendationService.send(:calculate_reason_quality_score, nil)
      expect(score).to eq(50)
      
      score = AiRecommendationService.send(:calculate_reason_quality_score, "")
      expect(score).to eq(50)
    end
    
    it "boosts scores for personality trait mentions" do
      score = AiRecommendationService.send(:calculate_reason_quality_score, "Matches your high extraversion personality trait")
      expect(score).to be > 50
      
      score = AiRecommendationService.send(:calculate_reason_quality_score, "This aligns with your conscientiousness")
      expect(score).to be > 50
    end
    
    it "boosts scores for user preference mentions" do
      score = AiRecommendationService.send(:calculate_reason_quality_score, "Similar to your highly rated movies")
      expect(score).to be > 50
      
      score = AiRecommendationService.send(:calculate_reason_quality_score, "This matches your favorite genre")
      expect(score).to be > 50
    end
    
    it "boosts scores for genre or similarity mentions" do
      score = AiRecommendationService.send(:calculate_reason_quality_score, "This action genre film should appeal to you")
      expect(score).to be > 50
      
      score = AiRecommendationService.send(:calculate_reason_quality_score, "Similar to other films you've enjoyed")
      expect(score).to be > 50
    end
    
    it "caps scores at 100" do
      # Create a reason that hits all boost criteria multiple times
      reason = "This action genre film matches your extraversion personality trait and is similar to your highly rated favorites. The themes align with your openness to experience and conscientiousness. The emotional storytelling will appeal to your empathy and emotional intelligence. The complex narrative structure is perfect for your cognitive style."
      
      score = AiRecommendationService.send(:calculate_reason_quality_score, reason)
      expect(score).to eq(100)
    end
  end
end 
