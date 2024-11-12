class Users::SessionsController < Devise::SessionsController
  def create
    super do |resource|
      if resource.persisted?
        if request.xhr?
          render json: { success: true, redirect: root_path } and return
        else
          redirect_to root_path and return
        end
      end
    end
  end
end
