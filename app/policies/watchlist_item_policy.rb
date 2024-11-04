class WatchlistItemPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(user: user)
    end
  end

  def create?
    user.present?
  end

  def destroy?
    user.present? && record.user == user
  end

  def status?
    user.present?
  end

  def reposition?
    user.present? && record.user == user
  end

  def toggle_watched?
    user.present? && record.user == user
  end

  def rate?
    record.user == user
  end

  private

  def user_owns_record?
    user == record.user
  end
end
