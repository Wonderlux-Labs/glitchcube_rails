# app/services/tools/music/search_music.rb
class Tools::Music::SearchMusic < Tools::BaseTool
  def self.description
    "Search for music tracks without playing them - useful for discovery and recommendations"
  end

  def self.narrative_desc
    "search for music - find specific tracks, artists, or albums in the music library"
  end

  def self.prompt_schema
    "search_music(query: 'Pink Floyd') - Search music library for tracks, artists, or albums"
  end

  def self.tool_type
    :sync # Search is informational, happens synchronously
  end

  def self.definition
    @definition ||= OpenRouter::Tool.define do
      name "search_music"
      description "Search the music library for tracks, artists, albums, or genres"

      parameters do
        string :query, required: true,
               description: "REQUIRED: What to search for - artist name, song title, album, or genre"

        string :search_type,
               description: "Optional: Type of search to perform",
               enum: [ "track", "artist", "album", "genre", "all" ]

        integer :limit,
                description: "Optional: Maximum number of results to return (default: 10)"
      end
    end
  end

  def call(query:, search_type: "all", limit: 10)
    # For now, this is a simple script call to Home Assistant
    # In the future, this could integrate with Music Assistant API directly

    service_data = {
      query: query,
      search_type: search_type,
      limit: limit
    }

    begin
      result = HomeAssistantService.call_service("script", "search_music_library", service_data)

      success_response(
        "Found music for: #{query}",
        search_query: query,
        search_type: search_type,
        limit: limit,
        results: result&.dig("results") || [],
        script: "search_music_library"
      )
    rescue HomeAssistantService::Error => e
      error_response("Failed to search music: #{e.message}")
    end
  end
end
