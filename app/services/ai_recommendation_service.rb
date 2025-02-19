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
    client = OpenAI::Client.new(
      access_token: ENV.fetch('OPENAI_API_KEY'),
      request_timeout: 60
    )
    
    response = client.chat(
      parameters: {
        model: config[:api_name],
        messages: [{
          role: "system",
          content: "You are a recommendation system. Respond only with valid JSON."
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
      Rails.logger.info "OpenAI Response: #{content}"
      parse_ai_response(content)
    rescue Faraday::TimeoutError => e
      Rails.logger.error "OpenAI request timed out: #{e.message}"
      []
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse OpenAI response: #{e.message}"
      []
    rescue StandardError => e
      Rails.logger.error "OpenAI API error: #{e.message}"
      Rails.logger.error "Response: #{response.inspect}"
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
        content: prompt
      }]
    })
    
    begin
      result = JSON.parse(response.body.to_s)
      Rails.logger.info "Raw Claude Response: #{result.inspect}"
      
      # Extract text from the first content item
      content = result.dig("content", 0, "text")
      Rails.logger.info "Extracted content: #{content}"
      
      parse_ai_response(content)
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
      system: "You are a recommendation system. Respond only with valid JSON.",
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
    <<~PROMPT
      Based on the user's profile below, recommend exactly 50 titles that match their preferences.
      Each recommendation should include a confidence score (0-100).
      
      User Profile:
      - Personality: #{user_data[:personality].to_json}
      - Favorite Genres: #{user_data[:favorite_genres].join(', ')}
      - Watch History: User has rated #{user_data[:watched_history].size} items.
        #{user_data[:watched_history].map { |w| "- #{w[:title]} (#{w[:year]}, #{w[:type]}) - #{w[:rating]}/10 - [#{w[:genres].join(', ')}]" }.join("\n        ")}
      
      Return in this format:
      {
        "recommendations": [
          {
            "title": "exact title",
            "type": "movie" or "tv",
            "year": release year (integer),
            "reason": "brief explanation of why this matches",
            "confidence_score": integer between 0-100
          }
        ]
      }
    PROMPT
  end

  def self.process_recommendations(recommendations, disable_adult_content)
    Rails.logger.info "Processing #{recommendations.size} AI recommendations"
    
    content_ids = []
    reasons = {}
    match_scores = {}
    
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
      reasons[content.id.to_s] = rec["reason"] if rec["reason"].present?
      
      # Calculate enhanced score
      ai_score = rec["confidence_score"] || 50
      genre_score = calculate_genre_match_score(content, rec["reason"])
      reason_score = calculate_reason_quality_score(rec["reason"])
      position_score = 100 - (recommendations.index(rec) * 2)
      
      # Weighted combination with higher AI weight
      final_score = (ai_score * 0.75) +           # AI's confidence (increased from 0.5)
                   (genre_score * 0.1) +         # Genre matching (decreased from 0.2)
                   (reason_score * 0.1) +        # Reason quality (decreased from 0.2)
                   (position_score * 0.05)        # Position bonus (unchanged)
                   
      match_scores[content.id.to_s] = final_score.round(1)
      
      Rails.logger.info "Added content: #{content.title} (ID: #{content.id})"
      Rails.logger.info "Scores - AI: #{ai_score}, Genre: #{genre_score}, Reason: #{reason_score}, Position: #{position_score}, Final: #{final_score}"
    end

    unique_ids = content_ids.uniq
    Rails.logger.info "Processed #{unique_ids.size} unique recommendations"
    
    [unique_ids.first(100), reasons, match_scores]
  end

  def self.calculate_genre_match_score(content, reason)
    return 50 unless reason.present? && content.genre_ids_array.present?
    
    # Extract genre mentions from reason
    mentioned_genres = Genre.all.map(&:name).select { |genre| reason.downcase.include?(genre.downcase) }
    
    # Calculate overlap with content's actual genres
    content_genres = Genre.where(tmdb_id: content.genre_ids_array).pluck(:name)
    matching_genres = (mentioned_genres & content_genres).size
    
    # Score based on genre match accuracy
    if matching_genres > 0
      base_score = 70 + (matching_genres * 10)
      [base_score, 100].min
    else
      50 # Default score when no genres match
    end
  end

  def self.calculate_reason_quality_score(reason)
    return 50 unless reason.present?
    
    score = 50 # base score
    
    # Boost for mentioning personality traits
    score += 20 if reason.downcase.include?("personality") || 
                   reason.downcase.include?("traits") ||
                   UserPreference::GENRE_MAPPING.keys.any? { |trait| reason.downcase.include?(trait.to_s) }
    
    # Boost for mentioning user preferences
    score += 20 if reason.downcase.include?("highly rated") || 
                   reason.downcase.include?("favorite") ||
                   reason.downcase.include?("watched") ||
                   reason.downcase.include?("rated")
    
    # Boost for specific genre or similarity mentions
    score += 10 if reason.downcase.include?("genre") || 
                   reason.downcase.include?("similar") ||
                   reason.downcase.include?("style") ||
                   reason.downcase.include?("themes")
    
    [score, 100].min # Cap at 100
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
