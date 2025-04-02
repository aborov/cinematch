class ServiceWorkerController < ActionController::Base
  skip_forgery_protection

  def service_worker; end
  def manifest; end
end
