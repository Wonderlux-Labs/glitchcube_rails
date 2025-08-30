class Api::V1::BurningManController < ApplicationController
  protect_from_forgery with: :null_session
  
  # POST /api/v1/burning_man/quest/progress
  def update_quest_progress
    increment = params[:increment]&.to_i || 1
    
    if GoalService.update_burning_man_quest_progress(increment)
      # Trigger goal refresh to pick up new progress
      GoalService.select_goal if GoalService.burning_man_quest_mode_active?
      
      render json: { 
        success: true, 
        message: "Quest progress updated",
        persona: CubePersona.current_persona
      }
    else
      render json: { 
        success: false, 
        error: "Failed to update quest progress" 
      }, status: 422
    end
  end

  # GET /api/v1/burning_man/quest/status  
  def quest_status
    return render json: { quest_mode_active: false } unless GoalService.burning_man_quest_mode_active?
    
    current_persona = CubePersona.current_persona
    return render json: { error: "No persona active" }, status: 422 unless current_persona

    # Load quest data
    themes_file = Rails.root.join("config", "persona_themes.yml")
    themes_data = YAML.load_file(themes_file) if File.exist?(themes_file)
    quest_data = themes_data&.dig("personas", current_persona, "burning_man_quest")

    if quest_data
      render json: {
        quest_mode_active: true,
        persona: current_persona,
        get_to_goal: quest_data["get_to_goal"],
        do_goal: quest_data["do_goal"],
        progress: quest_data["quest_progress"] || 0,
        max_progress: quest_data["max_progress"] || 1,
        completed: (quest_data["quest_progress"] || 0) >= (quest_data["max_progress"] || 1)
      }
    else
      render json: { error: "No quest data found for persona" }, status: 422
    end
  end
end