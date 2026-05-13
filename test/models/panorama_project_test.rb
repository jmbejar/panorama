require "test_helper"

class PanoramaProjectTest < ActiveSupport::TestCase
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  test "requires a title" do
    project = PanoramaProject.new
    assert_not project.valid?
    assert_includes project.errors[:title], "can't be blank"
  end

  test "defaults to draft status" do
    project = PanoramaProject.create!(title: "Test")
    assert_equal "draft", project.status
    assert project.draft?
  end

  test "status enum covers all spec values" do
    expected = %w[draft uploaded validating ready_to_process processing completed failed]
    assert_equal expected.sort, PanoramaProject.statuses.keys.sort
  end

  test "rejects unknown status values via validation" do
    project = PanoramaProject.new(title: "Test", status: "bogus")
    assert_not project.valid?
    assert_includes project.errors[:status], "is not included in the list"
  end

  test "source_photos are returned ordered by position" do
    project = PanoramaProject.create!(title: "Ordered")
    third = project.source_photos.create!(position: 3)
    first = project.source_photos.create!(position: 1)
    second = project.source_photos.create!(position: 2)

    assert_equal [ first, second, third ], project.source_photos.to_a
  end

  test "attach_photos creates SourcePhoto records with sequential positions and transitions to uploaded" do
    project = PanoramaProject.create!(title: "With photos")

    project.attach_photos([ uploaded_file, uploaded_file, uploaded_file ])

    assert_equal "uploaded", project.reload.status
    photos = project.source_photos.to_a
    assert_equal 3, photos.size
    assert_equal [ 1, 2, 3 ], photos.map(&:position)
    photos.each do |photo|
      assert photo.image.attached?, "expected image attached"
      assert_equal 1600, photo.width
      assert_equal 800, photo.height
      assert photo.file_size.to_i > 0
    end
  end

  test "attach_photos with empty input is a no-op" do
    project = PanoramaProject.create!(title: "Empty upload")

    assert_no_difference -> { SourcePhoto.count } do
      project.attach_photos(nil)
      project.attach_photos([])
      project.attach_photos([ "" ])
    end

    assert_equal "draft", project.reload.status
  end

  test "attach_photos tolerates nested arrays from malformed forms" do
    project = PanoramaProject.create!(title: "Nested params")

    assert_difference -> { project.source_photos.count }, 1 do
      project.attach_photos([ [ "" ], [ uploaded_file ] ])
    end
  end

  test "destroying a project removes its source photos" do
    project = PanoramaProject.create!(title: "Doomed")
    project.attach_photos([ uploaded_file ])

    assert_difference -> { SourcePhoto.count }, -1 do
      project.destroy
    end
  end

  test "stitchable? is true when uploaded with photos" do
    project = PanoramaProject.create!(title: "Ready")
    project.attach_photos([ uploaded_file ])

    assert project.stitchable?
  end

  test "stitchable? is false for draft (no photos)" do
    project = PanoramaProject.create!(title: "Draft")
    assert_not project.stitchable?
  end

  test "stitchable? is false while processing" do
    project = PanoramaProject.create!(title: "Working", status: "processing")
    project.source_photos.create!(position: 1)

    assert_not project.stitchable?
  end

  test "stitchable? is true when failed and has photos (retry path)" do
    project = PanoramaProject.create!(title: "Retry", status: "failed")
    project.source_photos.create!(position: 1)

    assert project.stitchable?
  end

  test "start_processing! sets status, timestamp, and clears prior result fields" do
    project = PanoramaProject.create!(
      title: "Restart",
      status: "failed",
      failure_reason: "old failure",
      stitching_logs: "old logs",
      stitching_engine: "fake",
      processing_finished_at: 1.hour.ago
    )

    project.start_processing!

    assert_equal "processing", project.status
    assert_not_nil project.processing_started_at
    assert_nil project.processing_finished_at
    assert_nil project.failure_reason
    assert_nil project.stitching_logs
    assert_nil project.stitching_engine
  end

  test "complete_with_result! attaches the final panorama image and stores logs" do
    project = PanoramaProject.create!(title: "Done")
    project.start_processing!
    result = StitchingResult.success(
      image_path: FakePanoramaStitcher::FIXTURE_PATH,
      engine: "fake",
      stdout: "ran"
    )

    project.complete_with_result!(result)

    assert_equal "completed", project.status
    assert project.final_panorama_image.attached?
    assert_equal "fake", project.stitching_engine
    assert_includes project.stitching_logs, "ran"
    assert_not_nil project.processing_finished_at
  end

  test "fail_with_result! records failure_reason and engine logs" do
    project = PanoramaProject.create!(title: "Sad")
    project.start_processing!
    result = StitchingResult.failure(engine: "fake", error_message: "no overlap", stderr: "details")

    project.fail_with_result!(result)

    assert_equal "failed", project.status
    assert_equal "no overlap", project.failure_reason
    assert_equal "fake", project.stitching_engine
    assert_includes project.stitching_logs, "details"
  end

  test "fail_with_error! records the exception class and message" do
    project = PanoramaProject.create!(title: "Exploded")
    project.start_processing!

    project.fail_with_error!(StitchingEngineError.new("Hugin crashed"))

    assert_equal "failed", project.status
    assert_match(/StitchingEngineError.*Hugin crashed/, project.failure_reason)
  end
end
