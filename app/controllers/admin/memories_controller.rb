# app/controllers/admin/memories_controller.rb

class Admin::MemoriesController < Admin::BaseController
  def index
    @memories = ConversationMemory.includes(:conversation)
                                 .order(created_at: :desc)
                                 .limit(100)
    
    if params[:type].present?
      @memories = @memories.by_type(params[:type])
    end
    
    if params[:importance].present?
      @memories = @memories.by_importance(params[:importance])
    end
    
    @memory_types = ConversationMemory::MEMORY_TYPES
    @type_counts = ConversationMemory.group(:memory_type).count
  end
  
  def show
    @memory = ConversationMemory.find(params[:id])
    @conversation = @memory.conversation
  end
  
  def search
    query = params[:q]
    if query.present?
      @memories = ConversationMemory.where("summary ILIKE ?", "%#{query}%")
                                   .order(created_at: :desc)
                                   .limit(50)
    else
      @memories = ConversationMemory.none
    end
    
    render :index
  end
  
  def by_type
    @type = params[:type]
    @memories = ConversationMemory.by_type(@type).recent.limit(50)
    render :index
  end
end