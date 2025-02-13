module SurveysHelper
  def show_welcome_modal?
    current_user.survey_responses.empty? && 
    !session[:welcome_modal_shown] && 
    params[:type] == 'basic'
  end
end 
