# frozen_string_literal: true

# Vector search / embeddings are disabled in this version — the langchainrb_rails
# and neighbor gems are commented out of the Gemfile and pgvector is no longer
# enabled. Restore the block below (and the gems) if memory search comes back.
#
# LangchainrbRails.configure do |config|
#   config.vectorsearch = Langchain::Vectorsearch::Pgvector.new(
#     llm: Langchain::LLM::OpenAI.new(
#       api_key: ENV["OPENROUTER_API_KEY"],
#       llm_options: { uri_base: "https://openrouter.ai/api/v1/" },
#       default_options: {
#         embeddings_model_name: "google/gemini-embedding-2",
#         dimensions: 1536
#       }
#     )
#   )
# end
