require "test_helper"

class FakePanoramaStitcherTest < ActiveSupport::TestCase
  test "engine_name is 'fake'" do
    assert_equal "fake", FakePanoramaStitcher.new.engine_name
  end

  test "stitch returns a successful StitchingResult pointing at the fixture image" do
    project = PanoramaProject.create!(title: "Fake")

    result = FakePanoramaStitcher.new.stitch(project)

    assert result.success?
    assert_equal "fake", result.engine
    assert_equal FakePanoramaStitcher::FIXTURE_PATH, result.image_path
    assert_predicate result.image_path, :exist?
    assert_includes result.stdout, "Fake stitcher"
  end

  test "stitch mentions the source photo count in stdout" do
    project = PanoramaProject.create!(title: "With photos")
    3.times { |i| project.source_photos.create!(position: i + 1) }

    result = FakePanoramaStitcher.new.stitch(project)

    assert_includes result.stdout, "stitch 3 photo"
  end
end
