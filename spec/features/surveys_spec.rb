require 'rails_helper'

RSpec.feature "Surveys", type: :feature, js: true do
  let(:user) { create(:user) }
  let!(:personality_questions) do
    [
      create(:survey_question,
             survey_type: 'personality',
             question_type: 'openness',
             question_text: 'I enjoy trying new things.',
             position: 1),
      create(:survey_question,
             survey_type: 'personality',
             question_type: 'conscientiousness',
             question_text: 'I am always prepared.',
             position: 2)
    ]
  end
  
  let(:tmdb_genres) do
    {
      user_facing_genres: [
        { "id" => 28, "name" => "Action" },
        { "id" => 35, "name" => "Comedy" }
      ]
    }
  end

  before do
    sign_in user
    allow(TmdbService).to receive(:fetch_genres).and_return(tmdb_genres)
  end

  scenario "User completes personality survey" do
    visit surveys_path
    
    # Wait for and close welcome modal if it appears
    if page.has_css?('#welcomeModal', wait: 5)
      sleep(1)
      find('.modal-footer .btn-primary').click
      expect(page).not_to have_css('#welcomeModal', wait: 5)
      expect(page).not_to have_css('.modal-backdrop', wait: 5)
    end
    
    # Answer first personality question
    expect(page).to have_content(personality_questions.first.question_text)
    page.execute_script(<<~JS)
      const radio = document.querySelector('#q#{personality_questions.first.id}_3');
      radio.checked = true;
      radio.dispatchEvent(new Event('change', { bubbles: true }));
    JS
    
    # Wait for second question to appear
    sleep(0.5)
    expect(page).to have_content(personality_questions.last.question_text)
    
    # Answer second personality question
    page.execute_script(<<~JS)
      const radio = document.querySelector('#q#{personality_questions.last.id}_4');
      radio.checked = true;
      radio.dispatchEvent(new Event('change', { bubbles: true }));
    JS
    
    # Wait for genre selection to appear
    sleep(0.5)
    expect(page).to have_content("Select your favorite genres")
    
    # Select favorite genres using hidden checkboxes
    page.execute_script(<<~JS)
      const actionCheckbox = document.querySelector('input[value="Action"]');
      const comedyCheckbox = document.querySelector('input[value="Comedy"]');
      actionCheckbox.checked = true;
      comedyCheckbox.checked = true;
      actionCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
      comedyCheckbox.dispatchEvent(new Event('change', { bubbles: true }));
    JS
    
    # Submit the form using JavaScript to bypass any event handlers
    page.execute_script("document.querySelector('form').removeEventListener('submit', function(){})")
    click_button "Submit"
    
    # Check for redirect and success message
    expect(page).to have_current_path(recommendations_path)
    expect(page).to have_content("Survey completed")
    expect(SurveyResponse.count).to eq(2)
    
    # Reload user preference to get updated data
    user.user_preference.reload
    expect(user.user_preference.favorite_genres).to include("Action", "Comedy")
  end
end 
