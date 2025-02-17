class AiRecommendationService
  def self.generate_recommendations(user_preference)
    Rails.logger.info "Starting recommendation generation for user #{user_preference.user_id}"
    Rails.logger.info "User preferences: #{user_preference.attributes}"
    
    user_data = prepare_user_data(user_preference)
    Rails.logger.info "Prepared user data: #{user_data}"
    
    response = get_ai_recommendations(user_data)
    Rails.logger.info "Got #{response&.size || 0} recommendations from AI"
    
    if response.blank?
      Rails.logger.error "No recommendations received from AI"
      return [[], {}]
    end
    
    process_recommendations(response, user_preference.disable_adult_content)
  end

  private

  def self.prepare_user_data(user_preference)
    watched_items = user_preference.user.watchlist_items
      .where(watched: true)
      .where.not(rating: nil)
      .includes(:content)
      .order(rating: :desc, updated_at: :desc)
      .limit(25)

    Rails.logger.info "Found #{watched_items.size} watched items"

    genre_names = Rails.cache.fetch("genre_names", expires_in: 1.day) do
      Genre.pluck(:tmdb_id, :name).to_h
    end

    formatted_items = watched_items.map do |item|
      next unless item.content # Skip if content is nil
      
      genre_ids = item.content.genre_ids_array
      genre_ids = genre_ids.is_a?(Array) ? genre_ids : [genre_ids].compact
      
      {
        title: item.content.title,
        rating: item.rating,
        genres: genre_ids.map { |id| genre_names[id.to_i] }.compact,
        year: item.content.release_year,
        type: item.content.content_type,
        highly_rated: item.rating >= 8
      }
    end.compact # Remove any nil entries

    {
      personality: user_preference.personality_profiles,
      favorite_genres: user_preference.favorite_genres,
      watched_history: formatted_items,
      has_strong_preferences: formatted_items.count { |i| i[:highly_rated] } >= 5
    }
  end

  def self.get_ai_recommendations(user_data)
    prompt = generate_prompt(user_data)
    Rails.logger.info "AI Prompt:\n#{prompt}"
    
    client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
    
    response = client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [{
          role: "system",
          content: "You are a movie recommendation system. Provide diverse recommendations without duplicates. Each recommendation should include title, type, year, and a reason for the recommendation."
        }, {
          role: "user",
          content: prompt
        }],
        temperature: 0.7,
        response_format: { type: "json_object" },
        max_tokens: 4000
      }
    )

    content = response.dig("choices", 0, "message", "content")
    Rails.logger.info "AI Response:\n#{content}"
    
    begin
      parsed = JSON.parse(content)
      # Ensure we're working with an array of recommendations
      recommendations = case parsed
                       when Array
                         parsed
                       when Hash
                         parsed["recommendations"] || parsed.values.first
                       else
                         []
                       end
      
      recommendations = [recommendations] unless recommendations.is_a?(Array)
      
      # Validate each recommendation has required fields
      recommendations.select! do |rec|
        rec.is_a?(Hash) && rec["title"].present? && rec["year"].present? && rec["type"].present?
      end
      
      Rails.logger.info "Processed #{recommendations.size} valid recommendations"
      
      # Remove duplicates based on title and year
      recommendations.uniq { |rec| [rec["title"].downcase, rec["year"]] }
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse AI response: #{e.message}"
      Rails.logger.error "Raw content: #{content}"
      []
    end
  end

  def self.generate_prompt(user_data)
    personality_description = user_data[:personality].map { |trait, score| 
      "#{trait}: #{score}/5"
    }.join(', ')
    
    highly_rated = user_data[:watched_history].select { |item| item[:highly_rated] }
    watched_description = if highly_rated.any?
      "Highly rated (8+ out of 10):\n" +
      highly_rated.map { |item| "#{item[:title]} (#{item[:rating]}/10) - #{item[:genres].join(', ')} [#{item[:type]}]" }.join("\n") +
      "\n\nOther watched:\n" +
      (user_data[:watched_history] - highly_rated).map { |item| 
        "#{item[:title]} (#{item[:rating]}/10) - #{item[:genres].join(', ')} [#{item[:type]}]"
      }.join("\n")
    else
      user_data[:watched_history].map { |item| 
        "#{item[:title]} (#{item[:rating]}/10) - #{item[:genres].join(', ')} [#{item[:type]}]"
      }.join("\n")
    end

    <<~PROMPT
      You are a content recommendation system for both movies and TV shows. Consider the following user profile:

      Personality traits: #{personality_description}
      Favorite genres: #{user_data[:favorite_genres].join(', ')}
      
      Recently watched and rated:
      #{watched_description}

      Based on this profile, recommend 50 titles with a balanced mix of movies and TV shows. Prioritize:
      1. Content similar to their highly rated content (8+ rating)
      2. Content matching their personality traits and genre preferences
      3. Content that combines multiple favorite genres
      4. For TV shows, consider both limited series and ongoing shows
      5. Include both classic and modern content when relevant

      Return recommendations in this exact JSON format:
      {
        "recommendations": [
          {
            "title": "exact title",
            "type": "movie" or "tv",
            "year": release year (integer),
            "reason": "brief explanation of why this matches the user's profile"
          }
        ]
      }

      Ensure accuracy of titles and years for correct matching. Aim for 40% TV shows.
    PROMPT
  end

  def self.process_recommendations(recommendations, disable_adult_content)
    Rails.logger.info "Processing #{recommendations.size} AI recommendations"
    
    content_ids = []
    reasons = {}
    
    recommendations.each do |rec|
      Rails.logger.info "Processing recommendation: #{rec['title']} (#{rec['year']})"
      contents = find_all_content_versions(rec)
      next if contents.empty?
      
      # Filter adult content if needed
      contents = contents.reject(&:adult?) if disable_adult_content
      next if contents.empty?
      
      # Get best matching content
      content = if rec["year"] && (year_match = contents.find { |c| c.release_year == rec["year"] })
        year_match
      else
        contents.first
      end
      
      content_ids << content.id
      # Store reason with content ID as key
      reasons[content.id.to_s] = rec["reason"] if rec["reason"].present?
      Rails.logger.info "Added content: #{content.title} (ID: #{content.id}) with reason: #{rec['reason']}"
    end

    unique_ids = content_ids.uniq
    Rails.logger.info "Processed #{unique_ids.size} unique recommendations with #{reasons.size} reasons"
    
    [unique_ids.first(100), reasons]
  end

  def self.find_all_content_versions(recommendation)
    Rails.logger.info "Searching for: #{recommendation["title"]} (#{recommendation["year"]}) - #{recommendation["type"]}"
    
    # Find all versions of the title
    contents = Content.where("LOWER(title) = ?", recommendation["title"].downcase)
    if contents.present?
      Rails.logger.info "Found exact match in database: #{contents.size} versions"
      return contents
    end

    # If exact match not found, try fuzzy search
    contents = Content.where("LOWER(title) LIKE ?", "%#{recommendation["title"].downcase}%")
    if contents.present?
      Rails.logger.info "Found fuzzy matches in database: #{contents.size} versions"
      
      # If year provided, filter by year
      if recommendation["year"] && (year_match = contents.find { |c| c.release_year == recommendation["year"] })
        Rails.logger.info "Found year-specific match: #{year_match.title} (#{year_match.release_year})"
        return [year_match]
      end
      
      return contents
    end

    # If not found, search TMDB
    Rails.logger.info "No matches in database, searching TMDB..."
    search_params = {
      title: recommendation["title"],
      year: recommendation["year"],
      type: recommendation["type"]
    }

    result = TmdbService.search(search_params)
    if result
      Rails.logger.info "Found match in TMDB: #{result['title'] || result['name']} (ID: #{result['id']})"
      TmdbTasks.update_content_batch([result])
      content = Content.find_by(source_id: result['id'])
      Rails.logger.info content ? "Successfully added to database" : "Failed to add to database"
      [content].compact
    else
      Rails.logger.warn "No matches found in TMDB"
      []
    end
  end
end 
