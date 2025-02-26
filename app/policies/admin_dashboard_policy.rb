# frozen_string_literal: true

class AdminDashboardPolicy < ApplicationPolicy
  def show?
    user.admin?
  end
end 
