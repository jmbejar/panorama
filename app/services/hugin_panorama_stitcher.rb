# Real stitching engine. Runs Hugin's CLI pipeline inside the panorama-hugin
# Docker image (see docker/hugin/) so the host doesn't need any of the Hugin
# tools installed.
#
# Build the image once with `bin/panorama-hugin-build`, then opt in by setting
# `PANORAMA_STITCHER=HuginPanoramaStitcher` (see config/initializers/panorama.rb).
#
# Failure taxonomy returned in StitchingResult.error_message:
#   - "Docker is not available …"         → docker binary missing on PATH
#   - "panorama-hugin image not found …"  → image hasn't been built locally
#   - "No source photos to stitch."       → workspace had nothing to feed in
#   - "Hugin completed but produced …"    → docker exit 0 but no panorama.jpg
#   - "Hugin stitching failed (…)"        → docker non-zero exit
require "open3"

class HuginPanoramaStitcher < PanoramaStitcher
  ENGINE_NAME       = "hugin".freeze
  IMAGE_TAG         = "panorama-hugin:latest".freeze
  DOCKER_NOT_FOUND  = 127

  def engine_name = ENGINE_NAME

  def stitch(project)
    workspace = PanoramaWorkspace.new(project)
    workspace.prepare!

    if workspace.input_files.empty?
      return StitchingResult.failure(
        engine: ENGINE_NAME,
        error_message: "No source photos to stitch.",
        stderr: "input directory empty"
      )
    end

    docker = run_container(workspace)
    docker_logs = workspace.collected_logs

    if docker[:exit_code] == 0 && workspace.output_image.exist?
      StitchingResult.success(
        image_path: workspace.output_image,
        engine: ENGINE_NAME,
        stdout: [ docker[:stdout], docker_logs ].compact_blank.join("\n\n"),
        stderr: docker[:stderr]
      )
    else
      StitchingResult.failure(
        engine: ENGINE_NAME,
        error_message: classify_failure(docker, workspace),
        stdout: [ docker[:stdout], docker_logs ].compact_blank.join("\n\n"),
        stderr: docker[:stderr],
        exit_code: docker[:exit_code]
      )
    end
    # Workspace cleanup intentionally NOT done here — the StitchingResult points
    # at workspace.output_image, and the caller (StitchPanoramaJob) needs to
    # read it before the directory can be removed. Job's ensure block cleans up.
  end

  # Extracted so tests can stub the docker invocation without forking docker.
  def run_container(workspace)
    stdout, stderr, status = Open3.capture3(
      "docker", "run", "--rm",
      "-v", "#{workspace.root_path}:/work",
      IMAGE_TAG
    )
    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus.to_i }
  rescue Errno::ENOENT => e
    { stdout: "", stderr: e.message, exit_code: DOCKER_NOT_FOUND }
  end

  private

  def classify_failure(docker, workspace)
    case
    when docker[:exit_code] == DOCKER_NOT_FOUND
      "Docker is not available. Install Docker and run bin/panorama-hugin-build."
    when image_missing?(docker[:stderr])
      "panorama-hugin image not found. Run bin/panorama-hugin-build to build it."
    when docker[:exit_code] != 0
      "Hugin stitching failed (exit #{docker[:exit_code]})."
    when !workspace.output_image.exist?
      "Hugin completed but produced no output image."
    else
      "Hugin stitching failed."
    end
  end

  def image_missing?(stderr)
    stderr.to_s.match?(/Unable to find image .*panorama-hugin/)
  end
end
