# Returns a fixed 2400×1200 placeholder panorama. Used to validate the workflow
# end-to-end before the real Hugin pipeline lands in Phase 3.
class FakePanoramaStitcher < PanoramaStitcher
  ENGINE_NAME = "fake".freeze
  FIXTURE_PATH = Rails.root.join("lib/panorama_stitcher/fake_panorama.jpg").freeze

  def engine_name = ENGINE_NAME

  def stitch(project)
    photo_count = project.source_photos.size

    unless FIXTURE_PATH.exist?
      return StitchingResult.failure(
        engine: ENGINE_NAME,
        error_message: "Fake panorama fixture missing at #{FIXTURE_PATH}",
        stderr: "fixture not found"
      )
    end

    StitchingResult.success(
      image_path: FIXTURE_PATH,
      engine: ENGINE_NAME,
      stdout: "Fake stitcher pretended to stitch #{photo_count} photo(s) for project ##{project.id}."
    )
  end
end
