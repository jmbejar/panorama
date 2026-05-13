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
  ensure
    # Clean up the stitcher's working directory only after complete_with_result!
    # has read result.image_path. PanoramaWorkspace.cleanup respects
    # PANORAMA_KEEP_WORKSPACE=1, so debug runs are still preserved.
    PanoramaWorkspace.new(project).cleanup if project
  end

  private

  def current_stitcher
    Rails.configuration.panorama_stitcher_class.constantize.new
  end
end
