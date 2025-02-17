class AiRecommendationService
  def self.generate_recommendations(user_preference)
    user_data = prepare_user_data(user_preference)
    response = get_ai_recommendations(user_data)
    process_recommendations(response, user_preference.disable_adult_content)
  end

  private

  def self.prepare_user_data(user_preference)
    {
      personality: user_preference.personality_profiles,
      favorite_genres: user_preference.favorite_genres,
      watched_history: user_preference.user.watchlist_items
        .where(watched: true)
        .includes(:content)
        .limit(10)
        .map { |item| format_watch_history(item) }
    }
  end

  def self.format_watch_history(item)
    {
      title: item.content.title,
      rating: item.rating,
      genres: Genre.where(tmdb_id: item.content.genre_ids_array).pluck(:name)
    }
  end

  def self.get_ai_recommendations(user_data)
    client = OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
    
    response = client.chat(
      parameters: {
        model: "gpt-3.5-turbo",
        messages: [{
          role: "system",
          content: "You are a movie recommendation system. Return only a JSON array of objects with 'title' and 'type' (movie/tv) keys."
        }, {
          role: "user",
          content: generate_prompt(user_data)
        }],
        temperature: 0.7
      }
    )

    JSON.parse(response.dig("choices", 0, "message", "content"))
  end

  def self.generate_prompt(user_data)
    <<~PROMPT
      Recommend 50 movies or TV shows for a user with:
      Personality traits: #{user_data[:personality].to_json}
      Favorite genres: #{user_data[:favorite_genres].join(', ')}
      Recently watched and liked: #{format_watch_history(user_data[:watched_history])}

      Return a JSON array of objects with the following structure:
      {
        "title": "exact title",
        "type": "movie" or "tv",
        "year": release year (optional),
        "director": "director name" (optional),
        "original_title": "title in original language" (optional)
      }

      Prioritize accuracy of titles to ensure correct matching.
    PROMPT
  end

  def self.process_recommendations(recommendations, disable_adult_content)
    content_ids = recommendations.map do |rec|
      content = find_or_fetch_content(rec)
      next if content.nil?
      next if disable_adult_content && content.adult?
      content.id
    end.compact

    content_ids.first(100)
  end

  def self.find_or_fetch_content(recommendation)
    # Try exact title match first
    content = Content.find_by("LOWER(title) = ?", recommendation["title"].downcase)
    return content if content

    # Try with year if provided
    if recommendation["year"]
      content = Content.where("LOWER(title) = ? AND release_year = ?", 
                            recommendation["title"].downcase, 
                            recommendation["year"]).first
      return content if content
    end

    # Try with original title if provided
    if recommendation["original_title"]
      content = Content.find_by("LOWER(original_title) = ?", recommendation["original_title"].downcase)
      return content if content
    end

    # If not found, search TMDB with enhanced criteria
    search_params = {
      title: recommendation["title"],
      year: recommendation["year"],
      type: recommendation["type"],
      director: recommendation["director"]
    }

    result = TmdbService.search(search_params)
    return nil unless result

    TmdbTasks.update_content_batch([result])
    Content.find_by(source_id: result['id'])
  end
end 
