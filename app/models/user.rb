# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  admin                  :boolean
#  deleted_at             :datetime
#  dob                    :date
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  gender                 :string
#  name                   :string
#  password_changed_at    :datetime
#  provider               :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  uid                    :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_deleted_at            (deleted_at)
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_provider_and_uid      (provider,uid) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#
class User < ApplicationRecord
  acts_as_paranoid

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :secure_validatable, :timeoutable,
         :omniauthable, omniauth_providers: [:google_oauth2, :facebook, :twitter, :apple]

  has_one :user_preference, dependent: :destroy
  has_many :survey_responses, dependent: :destroy

  validates :name, presence: true

  after_create :create_user_preference

  attr_accessor :skip_password_complexity

  scope :admins, -> { where(admin: true) }

  def admin?
    admin
  end

  def active_for_authentication?
    super && !deleted_at
  end

  def inactive_message
    !deleted_at ? super : :deleted_account
  end
  
  def ensure_user_preference
    create_user_preference if user_preference.nil?
  end

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
      user.skip_password_complexity = true
      
      case auth.provider
      when 'facebook'
        user.gender = auth.extra.raw_info.gender if auth.extra.raw_info.gender.present?
        if auth.extra.raw_info.birthday.present?
          user.dob = Date.strptime(auth.extra.raw_info.birthday, "%m/%d/%Y") rescue nil
        end
      when 'google_oauth2'
        user.gender = auth.info.gender if auth.info.gender.present?
        if auth.info.birthday.present?
          user.dob = Date.strptime(auth.info.birthday, "%Y-%m-%d") rescue nil
        end
      end
    end
  end

  private

  def create_user_preference
    create_user_preference!
  end

  def password_required?
    return false if skip_password_complexity
    super
  end
end
