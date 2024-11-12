# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard" do
  menu priority: 1, label: proc { I18n.t("active_admin.dashboard") }

  content title: proc { I18n.t("active_admin.dashboard") } do
    columns do
      column do
        panel "Content Overview" do
          div class: "dashboard-stats" do
            div class: "stat-box" do
              h3 "Total Content"
              h2 Content.count
            end
            div class: "stat-box" do
              h3 "Movies"
              h2 Content.where(content_type: 'movie').count
            end
            div class: "stat-box" do
              h3 "TV Shows"
              h2 Content.where(content_type: 'tv').count
            end
          end
          
          div class: "recent-content" do
            h3 "Recently Added Content"
            table_for Content.order(created_at: :desc).limit(5) do
              column :title
              column :content_type
              column :created_at
              column("Actions") { |content| link_to "View", admin_content_path(content) }
            end
          end

          div class: "trend-observations" do
            h3 "Content Growth Trends"
            last_month_count = Content.where('created_at > ?', 30.days.ago).count
            daily_avg = (last_month_count / 30.0).round(1)
            
            para "Last 30 days: #{last_month_count} new items added (avg. #{daily_avg}/day)"
            para "Most active content type: #{Content.where('created_at > ?', 30.days.ago).group(:content_type).count.max_by{|k,v| v}&.first || 'None'}"
          end
        end
      end

      column do
        panel "User Activity" do
          div class: "dashboard-stats" do
            div class: "stat-box" do
              h3 "Total Users"
              h2 User.count
            end
            div class: "stat-box" do
              h3 "Active Watchlists"
              h2 WatchlistItem.where('created_at > ?', 24.hours.ago).distinct.count('user_id')
            end
            div class: "stat-box" do
              h3 "New This Week"
              h2 User.where('created_at > ?', 1.week.ago).count
            end
          end
          
          div class: "activity-details" do
            h3 "Recent Activity"
            para "Survey Responses (7 days): #{SurveyResponse.where('created_at >= ?', 1.week.ago).count}"
            para "Watchlist Items Added (24h): #{WatchlistItem.where('created_at >= ?', 24.hours.ago).count}"
            para "Content Ratings (24h): #{WatchlistItem.where('rating IS NOT NULL').where('updated_at >= ?', 24.hours.ago).count}"
          end

          div class: "trend-observations" do
            h3 "User Engagement Trends"
            active_users = WatchlistItem.where('created_at > ?', 7.days.ago).distinct.count('user_id')
            rating_count = WatchlistItem.where('rating IS NOT NULL').where('updated_at > ?', 7.days.ago).count
            
            para "Active users (7 days): #{active_users}"
            para "New ratings (7 days): #{rating_count}"
            if rating_count > 0
              avg_rating = WatchlistItem.where('rating IS NOT NULL').where('updated_at > ?', 7.days.ago).average(:rating).round(1)
              para "Average rating: #{avg_rating}/10"
            end
          end
        end
      end

      column do
        panel "System Status" do
          div class: "job-stats" do
            h3 "Background Jobs"
            para "Running: #{GoodJob::Job.running.count}"
            para "Queued: #{GoodJob::Job.queued.count}"
            para "Failed: #{GoodJob::Job.where.not(error: nil).count}"
          end

          h3 "Next Scheduled Jobs"
          table_for GoodJob::Job.scheduled.limit(3) do
            column("Job") { |job| job.job_class }
            column("Scheduled For") { |job| job.scheduled_at }
          end
          
          div class: "actions" do
            link_to "View Job Dashboard", admin_good_job_dashboard_path, class: "button"
          end

          div class: "trend-observations" do
            h3 "Job Performance"
            jobs_24h = GoodJob::Job.where('created_at > ?', 24.hours.ago).count
            failed_24h = GoodJob::Job.where('created_at > ?', 24.hours.ago).where.not(error: nil).count
            
            para "Jobs run (24h): #{jobs_24h}"
            para "Success rate: #{((jobs_24h - failed_24h).to_f / jobs_24h * 100).round(1)}%" if jobs_24h > 0
            para "Most common job: #{GoodJob::Job.where('created_at > ?', 24.hours.ago).group(:job_class).count.max_by{|k,v| v}&.first || 'None'}"
          end
        end
      end
    end
  end
end
