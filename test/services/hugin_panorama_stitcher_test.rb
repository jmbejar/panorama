require "test_helper"

class HuginPanoramaStitcherTest < ActiveSupport::TestCase
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  def stitchable_project
    project = PanoramaProject.create!(title: "Hugin test")
    project.attach_photos([ uploaded_file, uploaded_file ])
    project
  end

  # A subclass that stubs only the docker invocation. Lets us assert the
  # wrapper logic (workspace prep, output detection, failure classification)
  # without forking docker.
  class StubbedHugin < HuginPanoramaStitcher
    attr_reader :captured_workspace

    def initialize(docker_response, write_output: false)
      @docker_response = docker_response
      @write_output = write_output
    end

    def run_container(workspace)
      @captured_workspace = workspace
      if @write_output
        FileUtils.mkdir_p(workspace.output_path)
        # 1x1 black JPEG so attach has a real file to read.
        FileUtils.cp(Rails.root.join("test/fixtures/files/test_photo.jpg"), workspace.output_image)
      end
      @docker_response
    end
  end

  test "engine_name is 'hugin'" do
    assert_equal "hugin", HuginPanoramaStitcher.new.engine_name
  end

  test "happy path: returns success result pointing at the output image" do
    project = stitchable_project

    result = nil
    ENV["PANORAMA_KEEP_WORKSPACE"] = "1"
    begin
      stitcher = StubbedHugin.new(
        { stdout: "Stitching ok", stderr: "", exit_code: 0 },
        write_output: true
      )
      result = stitcher.stitch(project)
    ensure
      ENV.delete("PANORAMA_KEEP_WORKSPACE")
    end

    assert result.success?
    assert_equal "hugin", result.engine
    assert_predicate result.image_path, :exist?
    assert_includes result.stdout, "Stitching ok"
  ensure
    FileUtils.rm_rf(PanoramaWorkspace.new(project).root_path)
  end

  test "docker exits zero but produces no output image → failure with output-missing message" do
    project = stitchable_project
    stitcher = StubbedHugin.new(
      { stdout: "ran but no file", stderr: "", exit_code: 0 },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/produced no output/, result.error_message)
  end

  test "docker exits non-zero → failure with exit code in message" do
    project = stitchable_project
    stitcher = StubbedHugin.new(
      { stdout: "", stderr: "cpfind: no control points found", exit_code: 1 },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/exit 1/, result.error_message)
    assert_includes result.stderr, "cpfind"
  end

  test "docker binary missing → failure tells the user to install Docker" do
    project = stitchable_project
    stitcher = StubbedHugin.new(
      { stdout: "", stderr: "No such file or directory - docker",
        exit_code: HuginPanoramaStitcher::DOCKER_NOT_FOUND },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/Docker is not available/, result.error_message)
  end

  test "docker run errors with 'Unable to find image' → failure tells the user to build the image" do
    project = stitchable_project
    stitcher = StubbedHugin.new(
      { stdout: "",
        stderr: "Unable to find image 'panorama-hugin:latest' locally",
        exit_code: 125 },
      write_output: false
    )

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/panorama-hugin image not found/, result.error_message)
  end

  test "project with no photos → failure without invoking docker" do
    project = PanoramaProject.create!(title: "No photos")
    docker_called = false
    stitcher = Class.new(HuginPanoramaStitcher) do
      define_method(:run_container) do |_workspace|
        docker_called = true
        { stdout: "", stderr: "", exit_code: 0 }
      end
    end.new

    result = stitcher.stitch(project)

    assert result.failure?
    assert_match(/No source photos/, result.error_message)
    assert_not docker_called
  end
end
