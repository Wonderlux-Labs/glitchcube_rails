# frozen_string_literal: true

module Services
  module Memory
    class ContextRetrievalService
      CONTEXT_DIR = 'data/context_documents'

      def initialize
        @documents = load_documents
        @retriever = create_retriever
      end

      # Retrieve relevant context for a given query
      def retrieve_context(query, k: 3)
        return [] if @documents.empty?

        # For now, use simple keyword matching
        # Later can upgrade to vector embeddings
        relevant_docs = find_relevant_documents(query, k)

        relevant_docs.map do |doc|
          {
            content: doc[:content],
            source: doc[:source],
            relevance: doc[:relevance]
          }
        end
      end

      # Add a new document to the context store
      def add_document(filename, content, metadata = {})
        doc_path = File.join(CONTEXT_DIR, filename)

        # Ensure directory exists
        FileUtils.mkdir_p(CONTEXT_DIR)

        # Save document
        File.write(doc_path, content)

        # Save metadata
        meta_path = "#{doc_path}.meta.json"
        File.write(meta_path, JSON.pretty_generate({
                                                     created_at: Time.now.iso8601,
                                                     updated_at: Time.now.iso8601,
                                                     **metadata
                                                   }))

        # Reload documents
        @documents = load_documents

        true
      rescue StandardError => e
        puts "Failed to add document: #{e.message}"
        false
      end

      # Get all available context documents
      def list_documents
        @documents.map do |doc|
          {
            source: doc[:source],
            title: doc[:metadata][:title] || File.basename(doc[:source]),
            size: doc[:content].length,
            created_at: doc[:metadata][:created_at]
          }
        end
      end

      private

      def load_documents
        return [] unless Dir.exist?(CONTEXT_DIR)

        Dir.glob(File.join(CONTEXT_DIR, '*.{txt,md}')).map do |file|
          content = File.read(file)
          meta_file = "#{file}.meta.json"

          metadata = if File.exist?(meta_file)
                       JSON.parse(File.read(meta_file), symbolize_names: true)
                     else
                       {}
                     end

          {
            source: file,
            content: content,
            metadata: metadata,
            keywords: extract_keywords(content)
          }
        end
      rescue StandardError => e
        puts "Failed to load documents: #{e.message}"
        []
      end

      def create_retriever
        # For future: Implement semantic search with embeddings when available
        # For now, we'll use keyword matching
        nil
      end

      def find_relevant_documents(query, k)
        query_keywords = extract_keywords(query)

        # Score each document based on keyword overlap
        scored_docs = @documents.map do |doc|
          score = calculate_relevance(query_keywords, doc[:keywords])
          doc.merge(relevance: score)
        end

        # Sort by relevance and take top k
        scored_docs
          .sort_by { |doc| -doc[:relevance] }
          .take(k)
          .select { |doc| doc[:relevance].positive? }
      end

      def extract_keywords(text)
        # Simple keyword extraction - lowercase and split
        words = text.downcase.split(/\W+/)

        # Remove common words
        stop_words = %w[the a an and or but in on at to for of with from by as is was are were been being have has had do
                        does did will would could should may might must can could]

        words.reject { |w| stop_words.include?(w) || w.length < 3 }.uniq
      end

      def calculate_relevance(query_keywords, doc_keywords)
        return 0.0 if query_keywords.empty? || doc_keywords.empty?

        # Calculate Jaccard similarity
        intersection = (query_keywords & doc_keywords).length
        union = (query_keywords | doc_keywords).length

        intersection.to_f / union
      end
    end
  end

  # Simple RAG implementation for Glitch Cube
  module Services
    class SimpleRAG
      def initialize
        @context_service = ContextRetrievalService.new
        @generator = create_generator
      end

      def answer_with_context(question, k: 3)
        # Retrieve relevant context
        contexts = @context_service.retrieve_context(question, k: k)

        if contexts.empty?
          # No context found, answer without it
          return generate_answer(question, [])
        end

        # Generate answer using retrieved context
        generate_answer(question, contexts)
      end

      private

      def create_generator
        # Use LLM service directly instead of Desiru
        Llm::LLMService
      end

      def generate_answer(question, contexts)
        context_text = contexts.map { |c| c[:content] }.join("\n\n---\n\n")

        prompt = "Based on the following context, answer the question:\n\nContext:\n#{context_text}\n\nQuestion: #{question}\n\nAnswer:"

        result = @generator.complete(
          system_prompt: 'You are a helpful assistant that answers questions based on provided context.',
          user_message: prompt,
          model: GlitchCube.config.default_ai_model,
          temperature: 0.7
        )

        {
          answer: result.response_text,
          contexts_used: contexts.map { |c| c[:source] },
          confidence: contexts.empty? ? 0.5 : 0.8
        }
      rescue StandardError => e
        puts "RAG generation failed: #{e.message}"
        {
          answer: "I'm having trouble accessing my memories right now. Let me think about that differently...",
          contexts_used: [],
          confidence: 0.3
        }
      end
    end
  end
end
