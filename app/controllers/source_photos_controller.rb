class SourcePhotosController < ApplicationController
  before_action :set_panorama_project

  def destroy
    unless @panorama_project.accepts_more_photos?
      redirect_to @panorama_project,
                  alert: "Photos can't be removed while this project is #{@panorama_project.status.humanize.downcase}."
      return
    end

    photo = @panorama_project.source_photos.find(params[:id])
    photo.destroy
    @panorama_project.renumber_source_photos!
    redirect_to @panorama_project, notice: "Photo removed."
  end

  private

  def set_panorama_project
    @panorama_project = PanoramaProject.find(params[:panorama_project_id])
  end
end
