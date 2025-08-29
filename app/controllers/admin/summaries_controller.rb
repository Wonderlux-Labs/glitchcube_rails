# frozen_string_literal: true

class Admin::SummariesController < Admin::BaseController
  before_action :set_summary, only: [ :show ]

  def index
    @summaries = Summary.recent

    # Filtering by type
    if params[:type].present? && Summary::SUMMARY_TYPES.include?(params[:type])
      @summaries = @summaries.by_type(params[:type])
    end

    # Date filtering
    if params[:date_range].present?
      case params[:date_range]
      when "today"
        @summaries = @summaries.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
      when "week"
        @summaries = @summaries.where(created_at: 1.week.ago..Time.current)
      when "month"
        @summaries = @summaries.where(created_at: 1.month.ago..Time.current)
      end
    end

    # Search
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @summaries = @summaries.where("summary_text ILIKE ? OR metadata ILIKE ?", search_term, search_term)
    end

    @summaries = @summaries.page(params[:page]).per(25)

    # Stats for dashboard
    @stats = {
      total_count: Summary.count,
      today_count: Summary.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      week_count: Summary.where(created_at: 1.week.ago..Time.current).count,
      by_type: Summary.group(:summary_type).count
    }
  end

  def show
    @metadata = @summary.metadata_json
    @related_summaries = Summary.where(summary_type: @summary.summary_type)
                                .where.not(id: @summary.id)
                                .recent
                                .limit(5)
  end

  def analytics
    @summary_trends = Summary.group(:summary_type)
                            .group_by_day(:created_at, last: 30)
                            .count

    @recent_activity = Summary.group_by_day(:created_at, last: 7).count

    @type_distribution = Summary.group(:summary_type).count

    @avg_message_counts = Summary.group(:summary_type)
                                .average(:message_count)
                                .transform_values { |v| v&.round(1) }

    # Duration analytics (where available)
    @avg_durations = Summary.where.not(start_time: nil, end_time: nil)
                           .group(:summary_type)
                           .average("EXTRACT(EPOCH FROM (end_time - start_time))")
                           .transform_values { |v| (v&./ 60)&.round(1) } # Convert to minutes

    # Recent goal completions
    @recent_goals = Summary.goal_completions.recent.limit(10)
  end

  def search
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @results = Summary.where("summary_text ILIKE ? OR metadata ILIKE ?", search_term, search_term)
                       .recent
                       .limit(20)

      render json: @results.map { |summary|
        {
          id: summary.id,
          summary_type: summary.summary_type,
          summary_text: summary.summary_text.truncate(200),
          message_count: summary.message_count,
          created_at: summary.created_at.strftime("%m/%d %H:%M"),
          duration_minutes: summary.duration_in_minutes
        }
      }
    else
      render json: []
    end
  end

  private

  def set_summary
    @summary = Summary.find(params[:id])
  end
end
