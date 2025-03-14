require 'rails_helper'

RSpec.feature "Recommendations", type: :feature, js: true do
  let(:user) { create(:user) }
  let(:user_preference) { user.user_preference }
  
  before do
    # Create genres
    create(:genre, :action)
    create(:genre, :adventure)
    create(:genre, :comedy)
    
    # Create content
    @action_movie = create(:content, :action, :with_poster, title: "Action Movie")
    @comedy_movie = create(:content, :comedy, :with_poster, title: "Comedy Movie")
    @adventure_movie = create(:content, :adventure, :with_poster, title: "Adventure Movie")
    
    # Set up user preferences
    user_preference.update(
      personality_profiles: {
        big_five: {
          openness: 50,
          conscientiousness: 50,
          extraversion: 90, # High extraversion -> Action, Adventure
          agreeableness: 50,
          neuroticism: 50
        }
      },
      favorite_genres: ['Action', 'Comedy']
    )
    
    # Generate recommendations
    user_preference.generate_recommendations
    
    # Sign in
    sign_in user
  end
  
  scenario "User views traditional recommendations" do
    user_preference.update(use_ai: false)
    user_preference.generate_recommendations
    
    visit recommendations_path
    
    expect(page).to have_content("Action Movie")
    expect(page).to have_content("Comedy Movie")
    
    # Should not show AI-specific elements
    expect(page).not_to have_css(".ai-recommendation-reason")
  end
  
  scenario "User views AI-powered recommendations" do
    # Set up AI recommendations
    user_preference.update(
      use_ai: true,
      ai_model: AiModelsConfig.default_model,
      recommended_content_ids: [@action_movie.id, @comedy_movie.id],
      recommendation_reasons: {
        @action_movie.id.to_s => "Matches your high extraversion trait",
        @comedy_movie.id.to_s => "One of your favorite genres"
      },
      recommendation_scores: {
        @action_movie.id.to_s => 95,
        @comedy_movie.id.to_s => 85
      }
    )
    
    visit recommendations_path
    
    # Should show content
    expect(page).to have_content("Action Movie")
    expect(page).to have_content("Comedy Movie")
    
    # Should show AI-specific elements
    expect(page).to have_content("Matches your high extraversion trait")
    expect(page).to have_content("One of your favorite genres")
    
    # Should show confidence scores
    expect(page).to have_content("95%")
    expect(page).to have_content("85%")
  end
  
  scenario "User refreshes recommendations" do
    visit recommendations_path
    
    # Mock the refresh endpoint
    allow_any_instance_of(RecommendationsController).to receive(:refresh).and_return(
      render json: { status: 'processing' }
    )
    
    # Click refresh button
    click_button "Refresh Recommendations"
    
    # Should show processing message
    expect(page).to have_content("Generating new recommendations")
  end
  
  scenario "User toggles between recommendation modes in preferences" do
    visit edit_user_preference_path
    
    # Toggle AI recommendations on
    check "Use AI-powered recommendations"
    
    # AI model options should appear
    expect(page).to have_select("user_preference[ai_model]")
    
    # Select a model
    select "GPT-4o Mini", from: "user_preference[ai_model]"
    
    click_button "Save Preferences"
    
    # Should redirect to recommendations with success message
    expect(page).to have_content("Preferences updated successfully")
    
    # User preference should be updated
    expect(user_preference.reload.use_ai).to be true
    expect(user_preference.ai_model).to eq("gpt-4o-mini")
  end
end 
