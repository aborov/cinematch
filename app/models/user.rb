# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :integer          not null, primary key
#  admin                  :boolean          default(FALSE)
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
    admin == true
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

  private

  def create_user_preference
    create_user_preference!
  end

  def password_required?
    return false if skip_password_complexity
    super
  end

  def self.ransackable_attributes(auth_object = nil)
    ["admin", "created_at", "deleted_at", "dob", "email", "gender", "id", "name", "provider", "uid", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user_preference", "survey_responses"]
  end

  attr_readonly :admin
end
