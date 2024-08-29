# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "Recent Users" do
          ul do
            User.order(created_at: :desc).limit(5).map do |user|
              li link_to(user.name, admin_user_path(user))
            end
          end
        end
      end

      column do
        panel "User Statistics" do
          para "Total Users: #{User.count}"
          para "Admin Users: #{User.admins.count}"
          para "Users created in the last 7 days: #{User.where('created_at >= ?', 1.week.ago).count}"
        end
      end

      column do
        panel "Content Statistics" do
          para "Total Contents: #{Content.count}"
          para "Movies: #{Content.where(content_type: 'movie').count}"
          para "TV Shows: #{Content.where(content_type: 'tv').count}"
        end
      end
    end

    columns do
      column do
        panel "Recent Survey Responses" do
          ul do
            SurveyResponse.order(created_at: :desc).limit(5).map do |response|
              li "User #{response.user.name} answered question #{response.survey_question.id}"
            end
          end
        end
      end

      column do
        panel "Activity Insights" do
          para "Survey Responses in the last 7 days: #{SurveyResponse.where('created_at >= ?', 1.week.ago).count}"
          para "User Preferences updated in the last 7 days: #{UserPreference.where('updated_at >= ?', 1.week.ago).count}"
        end
      end
    end

    panel "Quick Access" do
      ul do
        li link_to("Users", admin_users_path)
        li link_to("Contents", admin_contents_path)
        li link_to("Survey Questions", admin_survey_questions_path)
        li link_to("Survey Responses", admin_survey_responses_path)
        li link_to("User Preferences", admin_user_preferences_path)
      end
    end

    panel "Reports" do
      ul do
        li link_to "Download Users PDF", admin_users_path(format: :pdf)
        li link_to "Download User Preferences PDF", admin_user_preferences_path(format: :pdf)
        # Add more PDF download links for other resources here
      end
    end
  end

  action_item :view_site do
    link_to "Download Dashboard PDF", admin_dashboard_path(format: :pdf)
  end

  controller do
    def index
      super do |format|
        format.pdf do
          pdf = Prawn::Document.new do
            text "Dashboard Report", size: 18, style: :bold, align: :center
            move_down 20
            text "Total Users: #{User.count}"
            text "Total Contents: #{Content.count}"
            # Add more dashboard statistics here
          end
          send_data pdf.render, filename: 'dashboard.pdf', type: 'application/pdf', disposition: 'inline'
        end
      end
    end
  end
end
