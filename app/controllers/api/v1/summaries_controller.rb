# app/controllers/api/v1/summaries_controller.rb
class Api::V1::SummariesController < Api::V1::BaseController
  def recent
    limit = params[:limit]&.to_i || 3
    limit = [ limit, 10 ].min # Cap at 10

    summaries = Summary.recent.limit(limit).map do |summary|
      {
        id: summary.id,
        summary_type: summary.summary_type,
        summary_text: summary.summary_text,
        start_time: summary.start_time,
        end_time: summary.end_time,
        message_count: summary.message_count,
        created_at: summary.created_at,
        metadata: summary.metadata_json
      }
    end

    render json: { summaries: summaries }
  rescue StandardError => e
    Rails.logger.error "Failed to fetch recent summaries: #{e.message}"
    render json: { error: "Failed to fetch summaries", summaries: [] }, status: 500
  end
end
