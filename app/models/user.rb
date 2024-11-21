# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
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
#  warning_sent_at        :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_deleted_at            (deleted_at)
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_provider_and_uid      (provider,uid) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_warning_sent_at       (warning_sent_at)
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
  has_many :watchlist_items, dependent: :destroy
  has_many :watchlist_contents, through: :watchlist_items, source: :content

  validates :name, presence: true
  validate :validate_age

  after_create :create_user_preference

  attr_accessor :skip_password_complexity

  scope :admins, -> { where(admin: true) }
  scope :underage, -> { where("dob > ? AND dob IS NOT NULL", 13.years.ago.to_date) }
  scope :teenage, -> { where("dob > ? AND dob <= ? AND dob IS NOT NULL", 18.years.ago.to_date, 13.years.ago.to_date) }
  scope :adult, -> { where("dob <= ? AND dob IS NOT NULL", 18.years.ago.to_date) }
  scope :warned, -> { where.not(warning_sent_at: nil) }
  scope :not_warned, -> { underage.where(warning_sent_at: nil) }

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
    user_preference || create_user_preference
  end

  def validate_age
    return unless dob.present?
    return if dob.nil?  # Extra safety check
    
    if dob > 13.years.ago.to_date
      errors.add(:dob, "You must be at least 13 years of age to register")
    end
  end

  def underage?
    return false if dob.nil?
    dob > 13.years.ago.to_date
  end

  def send_underage_warning_email
    Rails.logger.info "Sending warning email to user #{id} (Before update: warning_sent_at=#{warning_sent_at})"
    
    # Send email first
    ContactMailer.underage_warning(self).deliver_later
    
    # Explicitly touch warning_sent_at
    current_time = Time.current
    update_result = update_column(:warning_sent_at, current_time)
    
    Rails.logger.info "Warning email update completed for user #{id}. Result: #{update_result}, New warning_sent_at=#{reload.warning_sent_at}"
    update_result
  end

  def should_validate_password?
    new_record? || password.present? || password_confirmation.present?
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
    ["admin", "created_at", "deleted_at", "dob", "email", "gender", "id", "name", "provider", "uid", "updated_at", "warning_sent_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["user_preference", "survey_responses"]
  end
end
