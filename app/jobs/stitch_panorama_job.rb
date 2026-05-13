class StitchPanoramaJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(panorama_project_id)
    project = PanoramaProject.find_by(id: panorama_project_id)
    return unless project
    return if project.completed?

    project.start_processing!

    result = current_stitcher.stitch(project)

    if result.success?
      project.complete_with_result!(result)
    else
      project.fail_with_result!(result)
    end
  rescue StandardError => e
    project&.fail_with_error!(e)
    raise
  end

  private

  def current_stitcher
    Rails.configuration.panorama_stitcher_class.constantize.new
  end
end
