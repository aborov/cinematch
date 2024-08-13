# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  admin                  :boolean
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

  has_one :user_preference, dependent: :nullify
  has_many  :survey_responses, dependent: :destroy

  validates :name, presence: true
  validates :gender, presence: true
  validates :dob, presence: true

  after_create :create_user_preference

  scope :admins, -> { where(admin: true) }

  def admin?
    self.admin
  end
  
  def ensure_user_preference
    self.create_user_preference if user_preference.nil?
  end
  
  private

  def create_user_preference
    self.create_user_preference!
  end

end
