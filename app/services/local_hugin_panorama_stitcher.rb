require "open3"

class LocalHuginPanoramaStitcher < PanoramaStitcher
  ENGINE_NAME = "hugin".freeze
  STITCH_SCRIPT = ENV.fetch("PANORAMA_STITCH_SCRIPT", "/usr/local/bin/stitch.sh").freeze
  SCRIPT_NOT_FOUND_EXIT = 127

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

    invocation = run_script(workspace)
    logs = workspace.collected_logs

    if invocation[:exit_code] == 0 && workspace.output_image.exist?
      StitchingResult.success(
        image_path: workspace.output_image,
        engine: ENGINE_NAME,
        stdout: [ invocation[:stdout], logs ].compact_blank.join("\n\n"),
        stderr: invocation[:stderr]
      )
    else
      StitchingResult.failure(
        engine: ENGINE_NAME,
        error_message: classify_failure(invocation, workspace, logs),
        stdout: [ invocation[:stdout], logs ].compact_blank.join("\n\n"),
        stderr: invocation[:stderr],
        exit_code: invocation[:exit_code]
      )
    end
  end

  # Extracted so tests can stub the shell invocation without forking the script.
  def run_script(workspace)
    stdout, stderr, status = Open3.capture3(
      { "WORKSPACE" => workspace.root_path.to_s },
      STITCH_SCRIPT
    )
    { stdout: stdout, stderr: stderr, exit_code: status.exitstatus.to_i }
  rescue Errno::ENOENT => e
    { stdout: "", stderr: e.message, exit_code: SCRIPT_NOT_FOUND_EXIT }
  end

  private

  def classify_failure(invocation, workspace, logs)
    friendly = classify_known_failure(logs)
    return friendly if friendly

    case
    when invocation[:exit_code] == SCRIPT_NOT_FOUND_EXIT
      "Stitch script not found at #{STITCH_SCRIPT}. Verify the production image build."
    when invocation[:exit_code] != 0
      "Hugin stitching failed (exit #{invocation[:exit_code]})."
    when !workspace.output_image.exist?
      "Hugin completed but produced no output image."
    else
      "Hugin stitching failed."
    end
  end

  # Pattern-match well-known Hugin / enblend failure modes against the
  # collected per-step logs and translate them into actionable messages.
  # The raw logs are still attached via stitching_logs for debugging.
  def classify_known_failure(logs)
    return nil if logs.blank?

    case logs
    when /excessive image overlap detected/
      "Some of your photos overlap too much (Hugin can't pick a seam). " \
      "Remove a near-duplicate photo from this project and try generating again."
    when /not enough features|insufficient feature/i
      "Hugin couldn't find enough matching points between photos. " \
      "Make sure adjacent photos overlap by about 30-40% and try again."
    when /no control points found/i
      "Hugin couldn't match your photos together. They may not share enough overlap, " \
      "or the camera moved between shots. Try retaking the sequence with more overlap."
    when /width or height exceeds limit/
      "The stitched panorama is too large for our processing limits. " \
      "Try generating with fewer photos."
    end
  end
end
