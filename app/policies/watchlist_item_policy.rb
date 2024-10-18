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
    user == record.user
  end

  def status?
    user.present?
  end

  def mark_watched?
    user_owns_record?
  end

  def mark_unwatched?
    user_owns_record?
  end

  def update_position?
    user.present? && record.user == user
  end

  private

  def user_owns_record?
    user == record.user
  end
end
