# frozen_string_literal: true

class SurveyPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def create?
    user.present?
  end

  def save_progress?
    user.present?
  end

  def results?
    user.present?
  end
end
