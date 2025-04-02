# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  admin                  :boolean          default(FALSE)
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  deleted_at             :datetime
#  dob                    :date
#  email                  :string           default(""), not null
#  encrypted_password     :string           default(""), not null
#  failed_attempts        :integer          default(0), not null
#  gender                 :string
#  last_active_at         :datetime
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  locked_at              :datetime
#  name                   :string
#  password_changed_at    :datetime
#  provider               :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  uid                    :string
#  unconfirmed_email      :string
#  unlock_token           :string
#  warning_sent_at        :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token) UNIQUE
#  index_users_on_deleted_at            (deleted_at)
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_last_active_at        (last_active_at)
#  index_users_on_provider_and_uid      (provider,uid) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#  index_users_on_warning_sent_at       (warning_sent_at)
#
class User < ApplicationRecord
  acts_as_paranoid

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :lockable, :trackable,
         :secure_validatable, :timeoutable,
         :omniauthable, omniauth_providers: [:google_oauth2, :facebook, :twitter, :apple]

  has_one :user_preference, dependent: :destroy
  has_many :survey_responses, dependent: :destroy
  has_many :watchlist_items, dependent: :destroy
  has_one :user_recommendation, dependent: :destroy
  has_many :watchlist_contents, through: :watchlist_items, source: :content

  validates :name, presence: true
  validate :validate_age

  after_create :create_user_preference

  attr_accessor :skip_password_complexity, :skip_age_validation

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

  def ensure_user_recommendation
    return user_recommendation if user_recommendation.present?
    
    Rails.logger.info "Creating user_recommendation for user #{id}"
    begin
      create_user_recommendation!
    rescue => e
      Rails.logger.error "Error creating user_recommendation: #{e.message}"
      # Try a second time with explicit parameters in case the first attempt failed
      UserRecommendation.create!(
        user_id: id,
        processing: false,
        recommended_content_ids: nil,
        recommendation_reasons: nil,
        recommendation_scores: nil
      )
    end
  end

  def validate_age
    return if skip_age_validation
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

  def touch_last_active
    update_column(:last_active_at, Time.current)
  end

  def basic_survey_completed?
    # First check if we have the cached value
    Rails.logger.debug "Checking basic_survey_completed for user #{id}"
    Rails.logger.debug "User preference: #{user_preference.inspect}"
    Rails.logger.debug "Cached basic_survey_completed: #{user_preference&.basic_survey_completed}"
    
    if user_preference&.basic_survey_completed.present?
      Rails.logger.debug "Using cached value: #{user_preference.basic_survey_completed}"
      return user_preference.basic_survey_completed 
    end
    
    # Fall back to calculating from responses if needed
    basic_questions_count = SurveyQuestion.where(survey_type: 'basic')
                                        .where.not(question_type: 'attention_check').count
    Rails.logger.debug "Basic questions count: #{basic_questions_count}"
    
    return false if basic_questions_count == 0
    
    user_basic_responses_count = survey_responses.joins(:survey_question)
                                               .where(survey_questions: { survey_type: 'basic' })
                                               .where.not(survey_questions: { question_type: 'attention_check' }).count
    Rails.logger.debug "User basic responses count: #{user_basic_responses_count}"
    
    # Lower threshold to 70% to account for attention check questions
    completion_threshold = 0.7 
    completed = user_basic_responses_count >= basic_questions_count * completion_threshold
    Rails.logger.debug "Basic survey completed? #{completed} (threshold: #{completion_threshold * 100}%)"
    
    # Cache the result if we have a user preference (using update_column to avoid callbacks)
    user_preference.update_column(:basic_survey_completed, completed) if user_preference
    Rails.logger.debug "Updated user_preference.basic_survey_completed to #{completed}"
    
    completed
  end
  
  def basic_survey_in_progress?
    # If basic is completed, it's not in progress
    return false if basic_survey_completed?
    
    # Check for any basic survey responses
    user_basic_responses_count = survey_responses.joins(:survey_question)
                                               .where("survey_questions.question_type LIKE 'big5_%' OR survey_questions.question_type LIKE 'ei_%'")
                                               .where.not(survey_questions: { question_type: 'attention_check' }).count
    in_progress = user_basic_responses_count > 0
    
    # Don't try to cache the result since there's no column for it
    in_progress
  end
  
  def extended_survey_completed?
    # First check if we have the cached value
    if user_preference&.extended_survey_completed.present?
      Rails.logger.debug "Using cached extended_survey_completed value: #{user_preference.extended_survey_completed}"
      return user_preference.extended_survey_completed 
    end
    
    # Fall back to calculating from responses if needed
    extended_questions_count = SurveyQuestion.where(survey_type: 'extended')
                                           .where.not(question_type: 'attention_check').count
    Rails.logger.debug "Extended questions count: #{extended_questions_count}"
    
    return false if extended_questions_count == 0
    
    user_extended_responses_count = survey_responses.joins(:survey_question)
                                                  .where(survey_questions: { survey_type: 'extended' })
                                                  .where.not(survey_questions: { question_type: 'attention_check' }).count
    Rails.logger.debug "User extended responses count: #{user_extended_responses_count}"
    
    # Lower threshold to 70% to account for attention check questions
    completion_threshold = 0.7
    completed = user_extended_responses_count >= extended_questions_count * completion_threshold
    Rails.logger.debug "Extended survey completed? #{completed} (threshold: #{completion_threshold * 100}%, ratio: #{user_extended_responses_count}/#{extended_questions_count})"
    
    # Cache the result if we have a user preference (using update_column to avoid callbacks)
    user_preference.update_column(:extended_survey_completed, completed) if user_preference
    Rails.logger.debug "Updated user_preference.extended_survey_completed to #{completed}"
    
    completed
  end
  
  def extended_survey_in_progress?
    # First check if we have the cached value
    if user_preference&.extended_survey_in_progress.present?
      Rails.logger.debug "Using cached extended_survey_in_progress value: #{user_preference.extended_survey_in_progress}"
      return user_preference.extended_survey_in_progress
    end
    
    # If extended is completed, it's not in progress
    return false if extended_survey_completed?
    
    # If basic survey isn't completed, extended survey can't be in progress
    return false if !basic_survey_completed?
    
    # Check for any extended survey responses
    user_extended_responses_count = survey_responses.joins(:survey_question)
                                                  .where(survey_questions: { survey_type: 'extended' })
                                                  .where.not(survey_questions: { question_type: 'attention_check' })
                                                  .count
    in_progress = user_extended_responses_count > 0
    Rails.logger.debug "Extended survey in progress? #{in_progress} (responses: #{user_extended_responses_count})"
    
    # Cache the result if we have a user preference (using update_column to avoid callbacks)
    user_preference.update_column(:extended_survey_in_progress, in_progress) if user_preference
    Rails.logger.debug "Updated user_preference.extended_survey_in_progress to #{in_progress}"
    
    in_progress
  end

  # Force refresh survey completion status for both surveys
  def refresh_survey_completion_status!
    # Clear cached values to force recalculation
    if user_preference
      user_preference.update_columns(
        basic_survey_completed: nil,
        extended_survey_completed: nil,
        extended_survey_in_progress: nil
      )
      
      Rails.logger.debug "Cleared survey completion status for user #{id}"
    end
    
    # Call methods to recalculate and store results
    basic_completed = basic_survey_completed?
    extended_completed = extended_survey_completed?
    basic_in_progress = basic_survey_in_progress?
    extended_in_progress = extended_survey_in_progress?
    
    Rails.logger.debug "Recalculated status: Basic completed: #{basic_completed}, Extended completed: #{extended_completed}"
    
    # Return the new status for convenience
    {
      basic_completed: basic_completed,
      extended_completed: extended_completed,
      basic_in_progress: basic_in_progress,
      extended_in_progress: extended_in_progress
    }
  end

  def responses_for_survey(survey_type)
    survey_responses.joins(:survey_question)
                    .where(survey_questions: { survey_type: survey_type.to_s })
                    .pluck(:survey_question_id, :response)
                    .to_h
  end

  def basic_survey_progress
    calculate_survey_progress('basic')
  end

  def extended_survey_progress
    calculate_survey_progress('extended')
  end

  def calculate_survey_progress(survey_type)
    # Get total number of questions for this survey type (excluding attention checks)
    total_questions = SurveyQuestion.where(survey_type: survey_type)
                                   .where.not(question_type: 'attention_check')
                                   .count
    
    # Get number of questions user has answered
    answered_questions = survey_responses.joins(:survey_question)
                                       .where(survey_questions: { survey_type: survey_type })
                                       .where.not(survey_questions: { question_type: 'attention_check' })
                                       .count
    
    return 0 if total_questions == 0
    (answered_questions.to_f / total_questions * 100).round
  end

  # Reset extended survey responses but keep basic ones
  def reset_extended_survey_responses!
    Rails.logger.info "Resetting extended survey responses for user #{id}"
    
    # Find extended survey questions
    extended_question_ids = SurveyQuestion.where(survey_type: 'extended').pluck(:id)
    
    # Delete only extended survey responses
    extended_responses = survey_responses.where(survey_question_id: extended_question_ids)
    deleted_count = extended_responses.destroy_all.count
    
    # Update cached flags
    if user_preference
      user_preference.update_columns(
        extended_survey_completed: false,
        extended_survey_in_progress: false
      )
    end
    
    Rails.logger.info "Deleted #{deleted_count} extended survey responses for user #{id}"
    
    # Return number of deleted responses
    deleted_count
  end
  
  # Reset basic survey responses and also extended ones
  def reset_basic_survey_responses!
    Rails.logger.info "Resetting basic survey responses for user #{id}"
    
    # First reset extended survey as they depend on basic
    reset_extended_survey_responses!
    
    # Find basic survey questions
    basic_question_ids = SurveyQuestion.where(survey_type: 'basic').pluck(:id)
    
    # Delete basic survey responses
    basic_responses = survey_responses.where(survey_question_id: basic_question_ids)
    deleted_count = basic_responses.destroy_all.count
    
    # Update cached flags
    if user_preference
      user_preference.update_columns(
        basic_survey_completed: false,
        extended_survey_completed: false,
        extended_survey_in_progress: false
      )
    end
    
    Rails.logger.info "Deleted #{deleted_count} basic survey responses for user #{id}"
    
    # Return number of deleted responses
    deleted_count
  end

  # Add methods for watchlist counts and recent items
  def unwatched_items_count
    watchlist_items.where(watched: false).count
  end

  def recent_watchlist_items(limit = 5)
    watchlist_items.where(watched: false).order(created_at: :desc).limit(limit)
  end

  private

  def create_user_preference
    user_preference || create_user_preference!
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
