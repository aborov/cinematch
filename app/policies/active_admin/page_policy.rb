module ActiveAdmin
  class PagePolicy < ApplicationPolicy
    def show?
      user.admin?
    end
  end
end
