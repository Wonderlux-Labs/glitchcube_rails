# frozen_string_literal: true

class Admin::PeopleController < Admin::BaseController
  before_action :set_person, only: [ :show, :edit, :update, :destroy ]

  def index
    @people = Person.includes(:related_summaries, :related_events)
                   .recent

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @people = @people.where("name ILIKE ? OR description ILIKE ?", search_term, search_term)
    end

    if params[:relationship].present?
      @people = @people.by_relationship(params[:relationship])
    end

    if params[:recent_only].present?
      @people = @people.seen_recently
    end

    @people = @people.page(params[:page]).per(25)

    # Stats for filters
    @total_count = Person.count
    @recent_count = Person.seen_recently.count
    @relationships = Person.distinct.pluck(:relationship).compact.sort
  end

  def show
    @related_summaries = @person.related_summaries.recent.limit(10)
    @related_events = @person.related_events.recent.limit(10)
  end

  def search
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @results = Person.where("name ILIKE ? OR description ILIKE ?", search_term, search_term)
                      .recent
                      .limit(20)

      render json: @results.map { |person|
        {
          id: person.id,
          name: person.name,
          description: person.description,
          relationship: person.relationship,
          last_seen_at: person.last_seen_at&.strftime("%m/%d %H:%M")
        }
      }
    else
      render json: []
    end
  end

  def edit
  end

  def update
    if @person.update(person_params)
      redirect_to admin_person_path(@person), notice: "Person updated successfully."
    else
      render :edit
    end
  end

  def destroy
    @person.destroy
    redirect_to admin_people_path, notice: "Person deleted successfully."
  end

  private

  def set_person
    @person = Person.find(params[:id])
  end

  def person_params
    params.require(:person).permit(:name, :description, :relationship, :metadata)
  end
end
