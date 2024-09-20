require_relative 'tmdb_tasks'

namespace :tmdb do
  desc 'Fix TV show types and content types'
  task fix_tv_show_types: :environment do
    start_time = Time.now
    puts "Starting to fix TV show types at #{start_time}"

    affected_records = Content.where.not(content_type: ['movie', 'tv']).or(Content.where(content_type: nil))
    total_count = affected_records.count
    puts "Found #{total_count} records to update"

    updated_count = 0

    affected_records.find_each do |content|
      new_content_type = 'tv'
      content.update(
        tv_show_type: content.content_type || content.tv_show_type,
        content_type: new_content_type
      )
      updated_count += 1

      if updated_count % 100 == 0
        progress = (updated_count.to_f / total_count * 100).round(2)
        puts "Progress: #{updated_count}/#{total_count} (#{progress}%)"
      end
    end

    end_time = Time.now
    puts "Finished fixing TV show types at #{end_time}. Total duration: #{(end_time - start_time).round(2)} seconds"
    puts "Updated #{updated_count} records"
  end
end
