require 'rails_helper'

RSpec.describe SurveyQuestion, type: :model do
  describe 'associations' do
    it { should have_many(:survey_responses) }
  end

  describe 'validations' do
    it { should validate_presence_of(:question_text) }
    it { should validate_presence_of(:question_type) }
    
    describe 'uniqueness' do
      subject { create(:survey_question) }
      it { should validate_uniqueness_of(:question_text).scoped_to(:question_type) }
    end
  end

  describe 'factory' do
    it 'has a valid factory' do
      expect(build(:survey_question)).to be_valid
    end
  end
end 
