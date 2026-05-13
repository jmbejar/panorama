# Owns the tmp/panorama_projects/:id/{input,output,logs} directory that every
# real stitching engine reads from and writes to. Decoupled from the stitcher
# so Phase 5 validation can reuse the same layout without invoking a stitcher.
#
# This is the temp directory layout the spec mandates:
#
#   tmp/panorama_projects/:project_id/
#     input/    — source photos downloaded from Active Storage
#     output/   — stitched result, picked up by complete_with_result!
#     logs/     — per-step Hugin logs, intermediate .pto files, etc.
class PanoramaWorkspace
  ROOT = Rails.root.join("tmp/panorama_projects")
  OUTPUT_FILENAME = "panorama.jpg".freeze

  attr_reader :project

  def initialize(project)
    @project = project
  end

  def root_path     = ROOT.join(project.id.to_s)
  def input_path    = root_path.join("input")
  def output_path   = root_path.join("output")
  def logs_path     = root_path.join("logs")
  def output_image  = output_path.join(OUTPUT_FILENAME)

  # Creates the directory tree (clean of any prior stitch attempt) and
  # downloads every attached source photo into input/, named with a zero-padded
  # position prefix so directory order matches capture order (cpfind cares
  # about this for --multirow).
  def prepare!
    FileUtils.rm_rf(root_path)
    FileUtils.mkdir_p([ input_path, output_path, logs_path ])

    project.source_photos.ordered.each do |photo|
      next unless photo.image.attached?

      target = input_path.join(input_filename_for(photo))
      File.open(target, "wb") do |f|
        photo.image.download { |chunk| f.write(chunk) }
      end
    end
  end

  def input_files
    return [] unless input_path.exist?
    Dir.children(input_path).sort.map { |name| input_path.join(name) }
  end

  # Persists per-step Hugin logs (named like 01_pto_gen.log) into the project
  # record as a single concatenated text blob. Useful for the failed-state UI.
  def collected_logs
    return "" unless logs_path.exist?

    Dir.children(logs_path).sort.map do |name|
      path = logs_path.join(name)
      next unless path.file?

      "=== #{name} ===\n#{path.read}\n"
    end.compact.join("\n")
  end

  def cleanup
    return if keep?
    FileUtils.rm_rf(root_path)
  end

  private

  def keep?
    ENV["PANORAMA_KEEP_WORKSPACE"].present?
  end

  def input_filename_for(photo)
    base = photo.filename.presence || "image_#{photo.id}.jpg"
    "%03d_%s" % [ photo.position, base ]
  end
end
