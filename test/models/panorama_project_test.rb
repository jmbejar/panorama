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

  test "destroying a project removes its source photos" do
    project = PanoramaProject.create!(title: "Doomed")
    project.attach_photos([ uploaded_file ])

    assert_difference -> { SourcePhoto.count }, -1 do
      project.destroy
    end
  end
end
