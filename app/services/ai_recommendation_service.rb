class AiRecommendationService
  def self.generate_recommendations(user_preference)
    Rails.logger.info "Starting recommendation generation for user #{user_preference.user_id}"
    
    model = user_preference.ai_model.presence || AiModelsConfig.default_model
    Rails.logger.info "Using AI model: #{model}"
    
    user_data = prepare_user_data(user_preference)
    response = get_ai_recommendations(user_data, model)
    process_recommendations(response, user_preference.disable_adult_content)
  end

  private

  def self.prepare_user_data(user_preference)
    watched_items = user_preference.user.watchlist_items
      .where(watched: true)
      .where.not(rating: nil)
      .includes(:content)
      .order(rating: :desc, updated_at: :desc)
      .limit(30)

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

  def self.get_ai_recommendations(user_data, model)
    prompt = generate_prompt(user_data)
    Rails.logger.info "AI Prompt:\n#{prompt}"
    
    model_config = AiModelsConfig::MODELS[model]
    
    case model_config[:provider]
    when :openai
      get_openai_recommendations(prompt, model_config)
    when :anthropic
      get_anthropic_recommendations(prompt, model_config)
    when :ollama
      get_ollama_recommendations(prompt, model_config)
    else
      Rails.logger.error "Unsupported AI provider: #{model_config[:provider]}"
      []
    end
  end

  def self.get_openai_recommendations(prompt, config)
    client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
    
    response = client.chat(
      parameters: {
        model: config[:api_name],
        messages: [{
          role: "system",
          content: "You are a recommendation system. Your responses must be valid JSON objects containing a 'recommendations' array. Do not include any text outside of the JSON structure."
        }, {
          role: "user",
          content: prompt
        }],
        temperature: config[:temperature],
        max_tokens: config[:max_tokens],
        response_format: { type: "json_object" }
      }
    )
    
    begin
      content = response.dig("choices", 0, "message", "content")
      Rails.logger.info "AI Response: #{content}"
      parse_ai_response(content)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse AI response: #{e.message}"
      []
    end
  end

  def self.get_anthropic_recommendations(prompt, config)
    response = HTTP.headers(
      "x-api-key" => ENV.fetch('ANTHROPIC_API_KEY'),
      "anthropic-version" => "2023-06-01",
      "content-type" => "application/json"
    ).post("https://api.anthropic.com/v1/messages", json: {
      model: config[:api_name],
      max_tokens: config[:max_tokens],
      temperature: config[:temperature],
      messages: [{
        role: "user",
        content: "#{prompt}\n\nRespond with valid JSON only, no additional text."
      }]
    })
    
    begin
      result = JSON.parse(response.body.to_s)
      Rails.logger.info "Raw Claude Response: #{result.inspect}"
      
      # Extract text from the first content item
      content = result.dig("content", 0, "text")
      Rails.logger.info "Extracted content: #{content}"
      
      # The content is already JSON, so we don't need to parse it again
      recommendations = JSON.parse(content)["recommendations"]
      Rails.logger.info "Parsed recommendations: #{recommendations.inspect}"
      recommendations
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse Claude response: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    rescue StandardError => e
      Rails.logger.error "Claude API error: #{e.message}"
      Rails.logger.error "Raw response: #{response.body.to_s}"
      []
    end
  end

  def self.get_ollama_recommendations(prompt, config)
    response = HTTP.post("http://localhost:11434/api/generate", json: {
      model: config[:api_name],
      prompt: prompt,
      system: "You are a recommendation system. Return recommendations as a valid JSON array.",
      temperature: config[:temperature]
    })
    
    parse_ai_response(response.body.to_s)
  end

  def self.parse_ai_response(content)
    return [] if content.blank?
    
    # Remove any markdown code block indicators if present
    content = content.gsub(/```json\n?/, '').gsub(/```\n?/, '')
    
    # Parse the JSON
    JSON.parse(content)["recommendations"]
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse AI response: #{e.message}"
    []
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
      return contents if recommendation["year"].nil?
      
      # If year provided, filter by year
      if (year_match = contents.find { |c| c.release_year == recommendation["year"] })
        Rails.logger.info "Found year-specific match: #{year_match.title} (#{year_match.release_year})"
        return [year_match]
      end
    end

    # If no matches in database, try TMDB
    Rails.logger.info "No matches in database, searching TMDB..."
    tmdb_result = TmdbService.search({
      title: recommendation["title"],
      year: recommendation["year"],
      type: recommendation["type"] || 'movie'
    })

    if tmdb_result
      Rails.logger.info "Found match in TMDB: #{tmdb_result['title'] || tmdb_result['name']} (ID: #{tmdb_result['id']})"
      require_relative '../../lib/tasks/tmdb_tasks'
      TmdbTasks.update_content_batch([tmdb_result])
      content = Content.find_by(source_id: tmdb_result['id'], content_type: tmdb_result['type'] || 'movie')
      return [content] if content
    end

    []
  end
end 
