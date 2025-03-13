# == Schema Information
#
# Table name: survey_responses
#
#  id                 :bigint           not null, primary key
#  deleted_at         :datetime
#  response           :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  survey_question_id :integer
#  user_id            :integer
#
# Indexes
#
#  index_survey_responses_on_deleted_at         (deleted_at)
#  index_survey_responses_on_user_and_question  (user_id,survey_question_id) UNIQUE WHERE (deleted_at IS NULL)
#
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
