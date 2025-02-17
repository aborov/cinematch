# == Schema Information
#
# Table name: survey_questions
#
#  id             :bigint           not null, primary key
#  correct_answer :string
#  position       :integer
#  question_text  :string
#  question_type  :string
#  survey_type    :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_survey_questions_on_survey_type  (survey_type)
#
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
