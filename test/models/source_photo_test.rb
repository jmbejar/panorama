require "test_helper"

class SourcePhotoTest < ActiveSupport::TestCase
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  test "populate_metadata_from_blob! fills filename, content_type, file_size, width, height" do
    project = PanoramaProject.create!(title: "Meta test")
    photo = project.source_photos.create!(position: 1)
    photo.image.attach(uploaded_file)

    photo.populate_metadata_from_blob!

    photo.reload
    assert_equal "test_photo.jpg", photo.filename
    assert_equal "image/jpeg", photo.content_type
    assert_equal 1600, photo.width
    assert_equal 800, photo.height
    assert photo.file_size > 0
  end

  test "populate_metadata_from_blob! is a no-op without an attached image" do
    project = PanoramaProject.create!(title: "No image")
    photo = project.source_photos.create!(position: 1)

    assert_nothing_raised { photo.populate_metadata_from_blob! }
    assert_nil photo.reload.filename
  end

  test "position must be unique within a panorama_project" do
    project = PanoramaProject.create!(title: "Unique positions")
    project.source_photos.create!(position: 1)
    duplicate = project.source_photos.build(position: 1)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:position], "has already been taken"
  end

  test "position can be reused across different projects" do
    project_a = PanoramaProject.create!(title: "A")
    project_b = PanoramaProject.create!(title: "B")

    assert project_a.source_photos.create(position: 1).persisted?
    assert project_b.source_photos.create(position: 1).persisted?
  end
end
