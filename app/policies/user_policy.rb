# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user.admin?
  end

  def show?
    user.admin? || record == user
  end

  def create?
    user.admin?
  end

  def new?
    create?
  end

  def update?
    user.admin? || record == user
  end

  def edit?
    update?
  end

  def destroy?
    user.admin? || record == user
  end

  def profile?
    user == record
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(id: user.id)
      end
    end
  end
end
