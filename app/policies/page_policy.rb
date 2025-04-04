# This policy delegates to ActiveAdmin::PagePolicy
# It's needed because policy(:page) looks for PagePolicy, not ActiveAdmin::PagePolicy
class PagePolicy < ApplicationPolicy
  def show?
    user.admin?
  end
  
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

  def delete_job?
    user.admin?
  end

  def admin?
    user.admin?
  end

  def check_job_runner?
    user.admin?
  end

  def manage?
    user.admin?
  end
end 
