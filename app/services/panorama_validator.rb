# Inspects a PanoramaProject's source photos and returns advisory warnings.
# Pure: never persists anything, returns a Result that the view renders.
#
# Per spec, warnings are advisory only — the user can always try to stitch,
# even with imperfect inputs. The MIN_RECOMMENDED_PHOTOS / MAX_RECOMMENDED_PHOTOS
# thresholds are presented as suggestions, not hard blocks.
class PanoramaValidator
  MIN_RECOMMENDED_PHOTOS = 6
  MAX_RECOMMENDED_PHOTOS = 60
  MIN_RECOMMENDED_WIDTH  = 1200
  ASPECT_RATIO_TOLERANCE = 0.2
  SMALL_FILE_BYTES       = 200_000

  Result = Struct.new(:project_warnings, :photo_warnings, keyword_init: true) do
    def warnings_for(photo)
      photo_warnings.fetch(photo.id, [])
    end

    def photos_with_warnings
      photo_warnings.keys
    end

    def any?
      project_warnings.any? || photo_warnings.values.any?(&:any?)
    end

    def total_count
      project_warnings.size + photo_warnings.values.sum(&:size)
    end
  end

  def self.validate(project) = new(project).validate

  def initialize(project)
    @project = project
    @photos = project.source_photos.to_a
  end

  def validate
    Result.new(
      project_warnings: project_warnings,
      photo_warnings: photo_warnings
    )
  end

  private

  def project_warnings
    warnings = []

    warnings << "Only #{count_label(@photos.size)} uploaded — full 360° stitching usually needs at least #{MIN_RECOMMENDED_PHOTOS}." if @photos.size.between?(1, MIN_RECOMMENDED_PHOTOS - 1)
    warnings << "#{@photos.size} photos is a lot — stitching anything over #{MAX_RECOMMENDED_PHOTOS} is unlikely to finish." if @photos.size > MAX_RECOMMENDED_PHOTOS

    if mixed_dimensions?
      warnings << "Photos have mixed dimensions — stitching may align imperfectly."
    end

    if mixed_aspect_ratios?
      warnings << "Photos have very different aspect ratios — best results come from a consistent camera/lens."
    end

    warnings
  end

  def photo_warnings
    Hash.new { |h, k| h[k] = [] }.tap do |result|
      @photos.each do |photo|
        if photo.width.to_i.positive? && photo.width.to_i < MIN_RECOMMENDED_WIDTH
          result[photo.id] << "Width #{photo.width}px is below the recommended #{MIN_RECOMMENDED_WIDTH}px minimum."
        end

        if photo.file_size.to_i.positive? && photo.file_size.to_i < SMALL_FILE_BYTES
          result[photo.id] << "Small file size (#{number_to_human_size(photo.file_size)}) — possibly heavily compressed."
        end
      end
    end.compact
  end

  def mixed_dimensions?
    dimensions = @photos.filter_map { |p| [ p.width, p.height ] if p.width && p.height }.uniq
    dimensions.size > 1
  end

  def mixed_aspect_ratios?
    aspects = @photos.filter_map { |p| p.width.to_f / p.height if p.width.to_i.positive? && p.height.to_i.positive? }
    return false if aspects.size < 2
    (aspects.max - aspects.min) > ASPECT_RATIO_TOLERANCE
  end

  def count_label(n)
    "#{n} photo#{n == 1 ? '' : 's'}"
  end

  def number_to_human_size(bytes)
    ActiveSupport::NumberHelper.number_to_human_size(bytes)
  end
end
