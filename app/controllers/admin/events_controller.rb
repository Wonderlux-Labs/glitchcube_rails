# frozen_string_literal: true

class Admin::EventsController < Admin::BaseController
  before_action :set_event, only: [ :show ]

  def index
    @events = Event.includes(:related_summaries)

    # Filtering
    if params[:type].present?
      @events = @events.where(event_type: params[:type])
    end

    if params[:importance].present?
      case params[:importance]
      when "high"
        @events = @events.high_importance
      when "medium"
        @events = @events.medium_importance
      when "low"
        @events = @events.low_importance
      end
    end

    if params[:status].present?
      case params[:status]
      when "upcoming"
        @events = @events.upcoming
      when "past"
        @events = @events.past
      end
    end

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @events = @events.where("title ILIKE ? OR description ILIKE ? OR location ILIKE ?",
                              search_term, search_term, search_term)
    end

    @events = @events.recent.page(params[:page]).per(25)

    # Stats for filters
    @total_count = Event.count
    @upcoming_count = Event.upcoming.count
    @high_importance_count = Event.high_importance.count
    @event_types = Event.distinct.pluck(:event_type).compact.sort
  end

  def show
    @related_events = Event.where(location: @event.location)
                          .where.not(id: @event.id)
                          .limit(5)
  end

  def timeline
    @events = Event.order(:event_time)

    if params[:days].present?
      days = params[:days].to_i
      start_date = days.days.ago
      end_date = days.days.from_now
      @events = @events.where(event_time: start_date..end_date)
    else
      # Default to next 30 days
      @events = @events.where(event_time: Time.current..(30.days.from_now))
    end

    @events = @events.limit(100)

    # Group events by date for timeline display
    @events_by_date = @events.group_by { |event| event.event_time&.to_date }
  end

  def search
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @results = Event.where("title ILIKE ? OR description ILIKE ? OR location ILIKE ?",
                            search_term, search_term, search_term)
                     .recent
                     .limit(20)

      render json: @results.map { |event|
        {
          id: event.id,
          title: event.title,
          description: event.description,
          location: event.location,
          event_time: event.formatted_time,
          importance: event.importance,
          upcoming: event.upcoming?
        }
      }
    else
      render json: []
    end
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end
end
