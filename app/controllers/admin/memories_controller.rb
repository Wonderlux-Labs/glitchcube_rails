# app/controllers/admin/memories_controller.rb

class Admin::MemoriesController < Admin::BaseController
  def index
    @memories = Memory.recent.limit(100)

    if params[:category].present?
      @memories = @memories.by_category(params[:category])
    end

    if params[:importance].present?
      @memories = @memories.where(importance: params[:importance])
    end

    @categories = Memory::CATEGORIES
    @category_counts = Memory.group(:category).count
  end

  def show
    @memory = Memory.find(params[:id])
  end

  def search
    query = params[:q]
    @memories = if query.present?
                  Memory.where("content ILIKE ?", "%#{query}%").recent.limit(50)
    else
                  Memory.none
    end

    render :index
  end

  def by_category
    @category = params[:category]
    @memories = Memory.by_category(@category).recent.limit(50)
    render :index
  end
end
