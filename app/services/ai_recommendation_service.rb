class AiRecommendationService
  def self.generate_recommendations(user_preference)
    user_data = prepare_user_data(user_preference)
    response = get_ai_recommendations(user_data)
    process_recommendations(response, user_preference.disable_adult_content)
  end

  private

  def self.prepare_user_data(user_preference)
    watched_items = user_preference.user.watchlist_items
      .where(watched: true)
      .where.not(rating: nil)  # Only include rated items
      .includes(:content)
      .order(rating: :desc, updated_at: :desc)  # Prioritize highly rated and recent
      .limit(15)  # Increase limit to get more context
      .map { |item| format_watch_history(item) }

    {
      personality: user_preference.personality_profiles,
      favorite_genres: user_preference.favorite_genres,
      watched_history: watched_items
    }
  end

  def self.format_watch_history(item)
    {
      title: item.content.title,
      rating: item.rating,
      genres: Genre.where(tmdb_id: item.content.genre_ids_array).pluck(:name),
      year: item.content.release_year,
      type: item.content.content_type
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
        temperature: 0.7
      }
    )

    recommendations = JSON.parse(response.dig("choices", 0, "message", "content"))
    
    # Remove duplicates based on title and year
    recommendations.uniq { |rec| [rec["title"].downcase, rec["year"]] }
  end

  def self.generate_prompt(user_data)
    personality_description = user_data[:personality].map { |trait, score| 
      "#{trait}: #{score}/5"
    }.join(', ')
    
    watched_description = user_data[:watched_history].map { |item| 
      "#{item[:title]} (#{item[:rating]}/10) - #{item[:genres].join(', ')}"
    }.join("\n")

    <<~PROMPT
      You are a movie recommendation system. Consider the following user profile:

      Personality traits: #{personality_description}
      Favorite genres: #{user_data[:favorite_genres].join(', ')}
      
      Recently watched and rated:
      #{watched_description}

      Based on this profile, recommend 50 movies or TV shows. Prioritize:
      1. Content matching their personality traits and genre preferences
      2. Similar to highly-rated watched content
      3. Include both classic and modern versions of stories when relevant

      Return a JSON array of objects with the following structure:
      {
        "title": "exact title",
        "type": "movie" or "tv",
        "year": release year (required),
        "director": "director name" (optional),
        "original_title": "title in original language" (optional),
        "reason": "brief explanation of why this matches the user's profile"
      }

      Ensure accuracy of titles and years for correct matching.
    PROMPT
  end

  def self.process_recommendations(recommendations, disable_adult_content)
    Rails.logger.info "AI Service received #{recommendations.size} recommendations from OpenAI"
    Rails.logger.info "Raw AI recommendations: #{recommendations.to_json}"
    
    content_ids = recommendations.map do |rec|
      possible_matches = find_all_content_versions(rec)
      next if possible_matches.empty?
      
      possible_matches = possible_matches.reject(&:adult?) if disable_adult_content
      next if possible_matches.empty?
      
      # If year is provided, prioritize exact year match
      if rec["year"] && (exact_match = possible_matches.find { |c| c.release_year == rec["year"] })
        exact_match.id
      else
        possible_matches.first.id
      end
    end.compact

    unique_ids = content_ids.uniq
    Rails.logger.info "Found #{content_ids.size} total content matches (#{unique_ids.size} unique)"
    Rails.logger.info "Duplicate IDs: #{content_ids.tally.select { |_, count| count > 1 }}" if content_ids.size != unique_ids.size
    
    unique_ids.first(100)
  end

  def self.find_all_content_versions(recommendation)
    # Find all versions of the title
    contents = Content.where("LOWER(title) = ?", recommendation["title"].downcase)
    return contents if contents.present?

    # If exact match not found, try fuzzy search
    contents = Content.where("LOWER(title) LIKE ?", "%#{recommendation["title"].downcase}%")
    
    # If year provided, filter by year
    if recommendation["year"] && contents.present?
      year_match = contents.find { |c| c.release_year == recommendation["year"] }
      return [year_match] if year_match
    end

    return contents if contents.present?

    # If not found, search TMDB
    search_params = {
      title: recommendation["title"],
      year: recommendation["year"],
      type: recommendation["type"]
    }

    result = TmdbService.search(search_params)
    return [] unless result

    TmdbTasks.update_content_batch([result])
    [Content.find_by(source_id: result['id'])].compact
  end
end 
