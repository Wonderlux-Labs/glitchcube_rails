# frozen_string_literal: true

class Admin::FactsController < Admin::BaseController
  before_action :set_fact, only: [ :show ]

  def index
    @facts = Fact.order(:id)

    # Search functionality
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      # Assuming facts have content and metadata fields similar to other models
      @facts = @facts.where("content ILIKE ? OR metadata ILIKE ?", search_term, search_term)
    end

    # Importance filtering (assuming facts have importance scoring)
    if params[:importance].present?
      case params[:importance]
      when "high"
        @facts = @facts.where("importance >= ?", 7)
      when "medium"
        @facts = @facts.where(importance: 4..6)
      when "low"
        @facts = @facts.where("importance <= ?", 3)
      end
    end

    @facts = @facts.page(params[:page]).per(25)

    # Stats for dashboard
    @total_count = Fact.count
    @high_importance_count = Fact.where("importance >= ?", 7).count rescue 0
    @recent_count = Fact.where("created_at > ?", 1.week.ago).count
  end

  def show
    # Display detailed fact information
    @metadata = begin
      if @fact.respond_to?(:metadata) && @fact.metadata.present?
        JSON.parse(@fact.metadata)
      else
        {}
      end
    rescue JSON::ParserError
      {}
    end

    # Find related facts (this would depend on your fact model structure)
    @related_facts = Fact.where.not(id: @fact.id)
                         .limit(5)
  end

  def search
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @results = Fact.where("content ILIKE ? OR metadata ILIKE ?", search_term, search_term)
                     .limit(20)

      render json: @results.map { |fact|
        {
          id: fact.id,
          content: fact.respond_to?(:content) ? fact.content&.truncate(200) : "Fact ##{fact.id}",
          importance: fact.respond_to?(:importance) ? fact.importance : nil,
          created_at: fact.created_at.strftime("%m/%d %H:%M")
        }
      }
    else
      render json: []
    end
  end

  private

  def set_fact
    @fact = Fact.find(params[:id])
  end
end
