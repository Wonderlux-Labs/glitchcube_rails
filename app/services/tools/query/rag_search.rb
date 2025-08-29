# app/services/tools/query/rag_search.rb
class Tools::Query::RagSearch < Tools::BaseTool
  def self.definition
    {
      type: "function",
      function: {
        name: "rag_search",
        description: "Search through past conversations, events, and people using RAG (semantic search)",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "What to search for (will be semantically matched against summaries, events, and people)"
            },
            type: {
              type: "string",
              enum: [ "all", "summaries", "events", "people" ],
              description: "What type of data to search (default: all)"
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 10,
              description: "Maximum number of results to return (default: 5)"
            }
          },
          required: [ "query" ]
        }
      }
    }
  end

  def self.description
    "Search past conversations, events, and people using semantic search to find relevant context and information"
  end

  def self.prompt_schema
    "rag_search(query: 'search term', type: 'all|summaries|events|people', limit: 5)"
  end

  def self.tool_type
    :sync
  end

  def call(query:, type: "all", limit: 5, **_args)
    return error_response("Query cannot be empty") if query.blank?

    limit = limit.clamp(1, 10)
    results = {}

    begin
      case type.downcase
      when "summaries"
        results[:summaries] = search_summaries(query, limit)
      when "events"
        results[:events] = search_events(query, limit)
      when "people"
        results[:people] = search_people(query, limit)
      else # "all"
        # Split limit across all types
        per_type = [ limit / 3, 1 ].max
        results[:summaries] = search_summaries(query, per_type)
        results[:events] = search_events(query, per_type)
        results[:people] = search_people(query, per_type)
      end

      total_results = results.values.sum(&:count)

      if total_results == 0
        return success_response(
          "No results found for '#{query}'",
          { query: query, type: type, results: results }
        )
      end

      success_response(
        "Found #{total_results} results for '#{query}'",
        {
          query: query,
          type: type,
          total_results: total_results,
          results: results
        }
      )

    rescue => e
      Rails.logger.error "RAG search error: #{e.message}"
      error_response("Search failed: #{e.message}")
    end
  end

  private

  def search_summaries(query, limit)
    return [] unless defined?(Summary) && Summary.respond_to?(:similarity_search)

    summaries = Summary.similarity_search(query).limit(limit)
    summaries.map do |summary|
      metadata = summary.metadata_json
      {
        id: summary.id,
        type: "summary",
        text: summary.summary_text,
        time_period: "#{summary.start_time&.strftime('%m/%d %H:%M')} - #{summary.end_time&.strftime('%H:%M')}",
        mood: metadata["general_mood"],
        message_count: summary.message_count,
        topics: metadata["topics"] || [],
        created_at: summary.created_at
      }
    end
  end

  def search_events(query, limit)
    return [] unless defined?(Event) && Event.respond_to?(:similarity_search)

    events = Event.similarity_search(query).limit(limit)
    events.map do |event|
      {
        id: event.id,
        type: "event",
        title: event.title,
        description: event.description,
        time: event.formatted_time,
        location: event.location,
        importance: event.importance,
        upcoming: event.upcoming?,
        created_at: event.created_at
      }
    end
  end

  def search_people(query, limit)
    return [] unless defined?(Person) && Person.respond_to?(:similarity_search)

    people = Person.similarity_search(query).limit(limit)
    people.map do |person|
      {
        id: person.id,
        type: "person",
        name: person.name,
        description: person.description,
        relationship: person.relationship,
        last_seen: person.last_seen_at&.strftime("%m/%d/%Y"),
        created_at: person.created_at
      }
    end
  end
end
