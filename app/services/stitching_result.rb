# Value object returned by every PanoramaStitcher implementation.
# Keep this as the single contract between stitchers and the job — Phase 3's
# Hugin stitcher must build the same shape from CLI output.
class StitchingResult
  attr_reader :image_path, :engine, :stdout, :stderr, :exit_code, :error_message

  def self.success(image_path:, engine:, stdout: "", stderr: "", exit_code: 0)
    new(success: true, image_path: image_path, engine: engine,
        stdout: stdout, stderr: stderr, exit_code: exit_code)
  end

  def self.failure(engine:, error_message:, stdout: "", stderr: "", exit_code: 1)
    new(success: false, engine: engine, error_message: error_message,
        stdout: stdout, stderr: stderr, exit_code: exit_code)
  end

  def initialize(success:, engine:, image_path: nil, stdout: "", stderr: "",
                 exit_code: 0, error_message: nil)
    @success = success
    @engine = engine
    @image_path = image_path
    @stdout = stdout.to_s
    @stderr = stderr.to_s
    @exit_code = exit_code
    @error_message = error_message
  end

  def success? = @success
  def failure? = !@success

  def combined_logs
    [ "[stdout]", stdout, "", "[stderr]", stderr ].join("\n")
  end
end
