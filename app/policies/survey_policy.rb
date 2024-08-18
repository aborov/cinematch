class SurveyPolicy < ApplicationPolicy
  def index?
    true
  end

  def create?
    user.present?
  end
end
