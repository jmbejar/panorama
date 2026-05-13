require "test_helper"

class LocalHuginPanoramaStitcherTest < ActiveSupport::TestCase
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  def stitchable_project
    project = PanoramaProject.create!(title: "Local Hugin test")
    project.attach_photos([ uploaded_file, uploaded_file ])
    project
  end

  # Stubs the shell invocation so we can exercise the wrapper logic
  # (workspace prep, output detection, failure classification) without
  # actually running /usr/local/bin/stitch.sh.
  class StubbedLocalHugin < LocalHuginPanoramaStitcher
    attr_reader :captured_workspace

    def initialize(invocation_response, write_output: false, log_file: nil)
      @invocation_response = invocation_response
      @write_output = write_output
      @log_file = log_file
    end

    def run_script(workspace)
      @captured_workspace = workspace
      if @write_output
        FileUtils.mkdir_p(workspace.output_path)
        FileUtils.cp(Rails.root.join("test/fixtures/files/test_photo.jpg"), workspace.output_image)
      end
      if @log_file
        FileUtils.mkdir_p(workspace.logs_path)
        File.write(workspace.logs_path.join(@log_file[:name]), @log_file[:content])
      end
      @invocation_response
    end
  end

  test "engine_name is 'hugin'" do
    assert_equal "hugin", LocalHuginPanoramaStitcher.new.engine_name
  end

  test "happy path: returns success result pointing at the output image" do
    project = stitchable_project
    stitcher = StubbedLocalHugin.new(
      { stdout: "Stitching ok", stderr: "", exit_code: 0 },
      write_output: true
    )

    result = stitcher.stitch(project)

    assert result.success?
    assert_equal "hugin", result.engine
    assert_predicate result.image_path, :exist?,
                     "stitcher must leave the output on disk for the job to read"
    assert_includes result.stdout, "Stitching ok"
  ensure
    FileUtils.rm_rf(PanoramaWorkspace.new(project).root_path) if project
  end

  test "script exits zero but produces no output image → failure with output-missing message" do
    project = stitchable_project
    stitcher = StubbedLocalHugin.new(
      { stdout: "ran but no file", stderr: "", exit_code: 0 },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/produced no output/, result.error_message)
  end

  test "script exits non-zero → failure with exit code in message" do
    project = stitchable_project
    stitcher = StubbedLocalHugin.new(
      { stdout: "", stderr: "cpfind: no control points found", exit_code: 1 },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/exit 1/, result.error_message)
    assert_includes result.stderr, "cpfind"
  end

  test "stitch script missing → failure tells the user the script path" do
    project = stitchable_project
    stitcher = StubbedLocalHugin.new(
      { stdout: "", stderr: "No such file or directory - /usr/local/bin/stitch.sh",
        exit_code: LocalHuginPanoramaStitcher::SCRIPT_NOT_FOUND_EXIT },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/Stitch script not found/, result.error_message)
  end

  test "excessive overlap in logs → user-friendly 'remove a near-duplicate' message" do
    project = stitchable_project
    enblend_msg = "enblend: excessive image overlap detected; too high risk of defective seam line"
    stitcher = StubbedLocalHugin.new(
      { stdout: "", stderr: enblend_msg, exit_code: 1 },
      write_output: false,
      log_file: { name: "06b_enblend.log", content: enblend_msg }
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/Remove a near-duplicate/, result.error_message)
    assert_no_match(/exit 1/, result.error_message,
                    "friendly message should replace the generic exit-code text")
  ensure
    FileUtils.rm_rf(PanoramaWorkspace.new(project).root_path) if project
  end

  test "project with no photos → failure without invoking the script" do
    project = PanoramaProject.create!(title: "No photos")
    script_called = false
    stitcher = Class.new(LocalHuginPanoramaStitcher) do
      define_method(:run_script) do |_workspace|
        script_called = true
        { stdout: "", stderr: "", exit_code: 0 }
      end
    end.new

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/No source photos/, result.error_message)
    assert_not script_called
  end
end
