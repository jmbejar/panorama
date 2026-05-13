class PanoramaProjectsController < ApplicationController
  before_action :set_panorama_project, only: [ :show, :destroy ]

  def index
    @panorama_projects = PanoramaProject.order(created_at: :desc)
  end

  def new
    @panorama_project = PanoramaProject.new
  end

  def create
    @panorama_project = PanoramaProject.new(panorama_project_params)

    if @panorama_project.save
      @panorama_project.attach_photos(params.dig(:panorama_project, :photos))
      redirect_to @panorama_project, notice: "Panorama project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def destroy
    @panorama_project.destroy
    redirect_to panorama_projects_path, notice: "Panorama project deleted."
  end

  private

  def set_panorama_project
    @panorama_project = PanoramaProject.find(params[:id])
  end

  def panorama_project_params
    params.require(:panorama_project).permit(:title)
  end
end
