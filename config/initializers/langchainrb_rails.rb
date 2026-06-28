# frozen_string_literal: true

LangchainrbRails.configure do |config|
  config.vectorsearch = Langchain::Vectorsearch::Pgvector.new(
    llm: Langchain::LLM::OpenAI.new(
      api_key: ENV["OPENROUTER_API_KEY"],
      llm_options: { uri_base: "https://openrouter.ai/api/v1/" },
      default_options: {
        embeddings_model_name: "google/gemini-embedding-2",
        dimensions: 1536
      }
    )
  )
end
