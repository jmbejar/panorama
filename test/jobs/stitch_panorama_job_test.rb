require "test_helper"

class StitchPanoramaJobTest < ActiveJob::TestCase
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  def stitchable_project
    project = PanoramaProject.create!(title: "Stitchable")
    project.attach_photos([ uploaded_file, uploaded_file ])
    project
  end

  test "happy path: transitions uploaded → completed, attaches the panorama, persists logs" do
    project = stitchable_project

    StitchPanoramaJob.perform_now(project.id)

    project.reload
    assert_equal "completed", project.status
    assert_equal "fake", project.stitching_engine
    assert project.final_panorama_image.attached?
    assert_not_nil project.processing_started_at
    assert_not_nil project.processing_finished_at
    assert_includes project.stitching_logs, "Fake stitcher"
    assert_nil project.failure_reason
  end

  test "failure path: stitcher returning a failure result transitions project to failed" do
    project = stitchable_project

    with_stitcher(FailingStubStitcher) do
      StitchPanoramaJob.perform_now(project.id)
    end

    project.reload
    assert_equal "failed", project.status
    assert_equal "stub", project.stitching_engine
    assert_equal "boom from stub", project.failure_reason
    assert_not project.final_panorama_image.attached?
  end

  test "raised exception transitions project to failed and re-raises" do
    project = stitchable_project

    error = assert_raises(RuntimeError) do
      with_stitcher(RaisingStubStitcher) do
        StitchPanoramaJob.perform_now(project.id)
      end
    end

    assert_equal "kaboom", error.message
    project.reload
    assert_equal "failed", project.status
    assert_match(/RuntimeError.*kaboom/, project.failure_reason)
  end

  test "skips work when project is already completed" do
    project = stitchable_project
    StitchPanoramaJob.perform_now(project.id)
    completed_at = project.reload.processing_finished_at

    travel 1.minute do
      StitchPanoramaJob.perform_now(project.id)
    end

    assert_equal completed_at.to_i, project.reload.processing_finished_at.to_i
  end

  test "returns silently when project no longer exists" do
    assert_nothing_raised { StitchPanoramaJob.perform_now(0) }
  end

  test "enqueues to the default queue" do
    project = PanoramaProject.create!(title: "Queue")

    assert_enqueued_with(job: StitchPanoramaJob, args: [ project.id ], queue: "default") do
      StitchPanoramaJob.perform_later(project.id)
    end
  end

  test "cleans up the panorama workspace after attaching the result" do
    project = stitchable_project
    workspace = PanoramaWorkspace.new(project)

    with_stitcher(WorkspaceWritingStubStitcher) do
      StitchPanoramaJob.perform_now(project.id)
    end

    project.reload
    assert_equal "completed", project.status
    assert project.final_panorama_image.attached?
    assert_not workspace.root_path.exist?,
               "job ensure block should remove the workspace once the file has been attached"
  end

  private

  def with_stitcher(klass)
    original = Rails.configuration.panorama_stitcher_class
    Rails.configuration.panorama_stitcher_class = klass.name
    yield
  ensure
    Rails.configuration.panorama_stitcher_class = original
  end

  class FailingStubStitcher < PanoramaStitcher
    def engine_name = "stub"
    def stitch(_project)
      StitchingResult.failure(engine: "stub", error_message: "boom from stub", stderr: "stub stderr")
    end
  end

  class RaisingStubStitcher < PanoramaStitcher
    def engine_name = "stub"
    def stitch(_project)
      raise "kaboom"
    end
  end

  # Simulates the Hugin path: builds the workspace, drops a file in output/,
  # returns a StitchingResult that points at it. Lets us assert the job —
  # not the stitcher — is the thing that cleans the workspace up.
  class WorkspaceWritingStubStitcher < PanoramaStitcher
    def engine_name = "ws_stub"
    def stitch(project)
      workspace = PanoramaWorkspace.new(project)
      workspace.prepare!
      FileUtils.cp(
        Rails.root.join("test/fixtures/files/test_photo.jpg"),
        workspace.output_image
      )
      StitchingResult.success(
        image_path: workspace.output_image,
        engine: "ws_stub",
        stdout: "ok"
      )
    end
  end
end
