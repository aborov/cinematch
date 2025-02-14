require 'rails_helper'

RSpec.describe SurveyResponse, type: :model do
  describe 'associations' do
    it { should belong_to(:user).required }
    it { should belong_to(:survey_question).required }
  end

  describe 'soft delete' do
    it 'can be soft deleted' do
      response = create(:survey_response)
      expect { response.destroy }.to change { response.deleted_at }.from(nil)
      expect(response).to be_persisted
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:survey_response)).to be_valid
    end
  end
end 
