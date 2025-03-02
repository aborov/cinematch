module ActiveAdmin
  class PagePolicy < ApplicationPolicy
    def show?
      user.admin?
    end
    
    # Add authorization for page actions
    def run_fetch_content?
      user.admin?
    end
    
    def run_fetch_new_content?
      user.admin?
    end
    
    def run_update_existing_content?
      user.admin?
    end
    
    def run_fill_missing_content_details?
      user.admin?
    end
    
    def run_update_recommendations?
      user.admin?
    end
    
    def run_fill_missing_details?
      user.admin?
    end
  end
end
