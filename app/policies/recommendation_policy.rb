# frozen_string_literal: true

class RecommendationPolicy < ApplicationPolicy
  def index?
    true
  end

  def show?
    true
  end

  def refresh?
    user.present?
  end
end
