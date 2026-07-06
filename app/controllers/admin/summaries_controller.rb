# frozen_string_literal: true

class Admin::SummariesController < Admin::BaseController
  before_action :set_summary, only: [ :show ]

  def index
    @latest_overall = Summary.overall.recent.first
    @latest_interaction = Summary.interaction.recent.first
    @latest_persona_summaries = Persona.active.order(:name).index_with do |persona|
      persona.summaries.persona.order(:created_at).last
    end

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

    @page = [ params[:page].to_i, 1 ].max
    @per_page = 25
    @total_count = @summaries.count
    @total_pages = (@total_count.to_f / @per_page).ceil
    @summaries = @summaries.limit(@per_page).offset((@page - 1) * @per_page)

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
    @previous_summary = @summary.previous_version
    @next_summary = @summary.next_version
    @version_number = @summary.version_number
    @version_count = @summary.version_count

    @related_summaries = @summary.chain
                                .where.not(id: @summary.id)
                                .recent
                                .limit(5)
  end

  def analytics
    # No groupdate gem in this app — group by day with a plain SQL DATE() truncation.
    @summary_trends = Summary.where(created_at: 30.days.ago..Time.current).group(:summary_type).count
    @recent_activity = group_by_day(Summary.where(created_at: 7.days.ago..Time.current))

    @type_distribution = Summary.group(:summary_type).count

    @avg_message_counts = Summary.group(:summary_type)
                                .average(:message_count)
                                .transform_values { |v| v&.round(1) }

    # Duration analytics (where available)
    @avg_durations = Summary.where.not(start_time: nil, end_time: nil)
                           .group(:summary_type)
                           .average("EXTRACT(EPOCH FROM (end_time - start_time))")
                           .transform_values { |v| (v&./ 60)&.round(1) } # Convert to minutes

    # Recent director/persona steering notes (ooc_note) across all types — the
    # current equivalent of "things worth an operator's attention".
    @recent_ooc_notes = Summary.where("metadata ILIKE ?", "%\"ooc_note\":%")
                              .recent
                              .limit(10)
                              .select { |s| s.metadata_json["ooc_note"].present? }
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

  def group_by_day(scope)
    scope.group("DATE(created_at)").count.transform_keys { |k| k.is_a?(String) ? Date.parse(k) : k }
  end

  def set_summary
    @summary = Summary.find(params[:id])
  end
end
