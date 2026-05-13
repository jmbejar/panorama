class PanoramaProjectsController < ApplicationController
  before_action :set_panorama_project, only: [ :show, :destroy, :generate, :add_photos ]

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
    @validation = PanoramaValidator.validate(@panorama_project)
  end

  def destroy
    @panorama_project.destroy
    redirect_to panorama_projects_path, notice: "Panorama project deleted."
  end

  def generate
    unless @panorama_project.stitchable?
      redirect_to @panorama_project,
                  alert: "This project can't be stitched yet — upload photos first."
      return
    end

    StitchPanoramaJob.perform_later(@panorama_project.id)
    redirect_to @panorama_project, notice: "Stitching started. This page will refresh while we work on your panorama."
  end

  def add_photos
    unless @panorama_project.accepts_more_photos?
      redirect_to @panorama_project,
                  alert: "Photos can't be added while this project is #{@panorama_project.status.humanize.downcase}."
      return
    end

    files = params.dig(:panorama_project, :photos)
    @panorama_project.attach_photos(files)
    redirect_to @panorama_project, notice: "Photos added."
  end

  private

  def set_panorama_project
    @panorama_project = PanoramaProject.find(params[:id])
  end

  def panorama_project_params
    params.require(:panorama_project).permit(:title)
  end
end
