require "test_helper"

class PanoramaValidatorTest < ActiveSupport::TestCase
  def make_photo(project, attrs = {})
    project.source_photos.create!({
      position: (project.source_photos.maximum(:position) || 0) + 1,
      width: 1600,
      height: 800,
      file_size: 500_000
    }.merge(attrs))
  end

  test "no warnings for a healthy 6+ photo project with consistent dimensions" do
    project = PanoramaProject.create!(title: "Healthy")
    6.times { make_photo(project) }

    result = PanoramaValidator.validate(project)

    assert_not result.any?
    assert_equal [], result.project_warnings
  end

  test "warns when photo count is below recommended minimum" do
    project = PanoramaProject.create!(title: "Few photos")
    3.times { make_photo(project) }

    result = PanoramaValidator.validate(project)

    assert_match(/Only 3 photos uploaded/, result.project_warnings.first)
    assert_match(/at least 6/, result.project_warnings.first)
  end

  test "warns when photo count exceeds recommended maximum" do
    project = PanoramaProject.create!(title: "Too many")
    61.times { make_photo(project) }

    result = PanoramaValidator.validate(project)

    assert_match(/61 photos is a lot/, result.project_warnings.first)
  end

  test "warns about mixed dimensions" do
    project = PanoramaProject.create!(title: "Mixed dims")
    make_photo(project, width: 1600, height: 800)
    make_photo(project, width: 1920, height: 800)

    result = PanoramaValidator.validate(project)

    assert(result.project_warnings.any? { |w| w =~ /mixed dimensions/ })
  end

  test "warns about diverging aspect ratios" do
    project = PanoramaProject.create!(title: "Mixed aspects")
    make_photo(project, width: 1600, height: 800)   # 2.0
    make_photo(project, width: 1600, height: 900)   # 1.78
    make_photo(project, width: 1600, height: 1600)  # 1.0

    result = PanoramaValidator.validate(project)

    assert(result.project_warnings.any? { |w| w =~ /aspect ratios/ })
  end

  test "per-photo warning when width below 1200" do
    project = PanoramaProject.create!(title: "Narrow")
    skinny = make_photo(project, width: 800, height: 400)
    fat    = make_photo(project, width: 1600, height: 800)

    result = PanoramaValidator.validate(project)

    assert_includes result.warnings_for(skinny).join, "800px is below the recommended 1200px"
    assert_empty result.warnings_for(fat)
  end

  test "per-photo warning when file size is suspiciously small" do
    project = PanoramaProject.create!(title: "Tiny files")
    tiny = make_photo(project, file_size: 50_000)
    big  = make_photo(project, file_size: 500_000)

    result = PanoramaValidator.validate(project)

    assert_includes result.warnings_for(tiny).join, "Small file size"
    assert_empty result.warnings_for(big)
  end

  test "warnings_for returns [] when photo has none" do
    project = PanoramaProject.create!(title: "Single happy photo")
    photo = make_photo(project)

    result = PanoramaValidator.validate(project)

    assert_equal [], result.warnings_for(photo)
  end

  test "validator is pure — does not persist anything on source photos" do
    project = PanoramaProject.create!(title: "Pure check")
    photo = make_photo(project, width: 100, height: 100, file_size: 100)

    PanoramaValidator.validate(project)

    photo.reload
    assert_nil photo.validation_status
    assert_nil photo.validation_warnings
  end
end
