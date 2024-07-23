# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  dob                    :date
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  gender                 :string
#  name                   :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :user_preferences, class_name: "UserPreference", foreign_key: "user_id", dependent: :nullify
  has_many  :survey_responses, class_name: "SurveyResponse", foreign_key: "user_id", dependent: :destroy

  validates :name, presence: true
  validates :gender, presence: true
  validates :dob, presence: true
end
