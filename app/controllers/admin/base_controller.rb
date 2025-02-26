module Admin
  class BaseController < ApplicationController
    before_action :authenticate_admin_user!
    layout 'active_admin'
    
    def skip_authorization?
      true
    end
  end
end 
