require "test_helper"

class PanoramaWorkspaceTest < ActiveSupport::TestCase
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  def stitchable_project
    project = PanoramaProject.create!(title: "Workspace test")
    project.attach_photos([ uploaded_file, uploaded_file, uploaded_file ])
    project
  end

  def workspace_for(project)
    PanoramaWorkspace.new(project).tap do |w|
      # Tests run in parallel & leave files on disk — clean any prior workspace
      # for the same project id before exercising prepare!.
      FileUtils.rm_rf(w.root_path)
    end
  end

  test "prepare! creates the {input, output, logs} tree" do
    workspace = workspace_for(stitchable_project)

    workspace.prepare!

    assert_predicate workspace.input_path, :exist?
    assert_predicate workspace.output_path, :exist?
    assert_predicate workspace.logs_path, :exist?
  ensure
    workspace&.cleanup
  end

  test "prepare! downloads every attached source photo into input/" do
    project = stitchable_project
    workspace = workspace_for(project)

    workspace.prepare!

    files = workspace.input_files
    assert_equal project.source_photos.size, files.size
    files.each { |f| assert File.size(f) > 0, "expected #{f} to have content" }
  ensure
    workspace&.cleanup
  end

  test "downloaded filenames are zero-padded by position to preserve capture order" do
    project = stitchable_project
    workspace = workspace_for(project)

    workspace.prepare!

    names = workspace.input_files.map { |p| File.basename(p) }
    assert_equal names, names.sort, "filenames should sort in position order"
    assert_match(/\A\d{3}_/, names.first)
  ensure
    workspace&.cleanup
  end

  test "collected_logs concatenates per-step log files in sorted order" do
    project = stitchable_project
    workspace = workspace_for(project)
    workspace.prepare!
    File.write(workspace.logs_path.join("01_pto_gen.log"), "pto gen output")
    File.write(workspace.logs_path.join("02_cpfind.log"), "cpfind output")

    logs = workspace.collected_logs

    assert_match(/=== 01_pto_gen\.log ===\npto gen output/, logs)
    assert_match(/=== 02_cpfind\.log ===\ncpfind output/, logs)
    assert logs.index("01_pto_gen") < logs.index("02_cpfind"),
           "01 entry should appear before 02 entry"
  ensure
    workspace&.cleanup
  end

  test "cleanup removes the workspace by default" do
    workspace = workspace_for(stitchable_project)
    workspace.prepare!
    assert_predicate workspace.root_path, :exist?

    workspace.cleanup

    assert_not workspace.root_path.exist?
  end

  test "cleanup keeps the workspace when PANORAMA_KEEP_WORKSPACE is set" do
    workspace = workspace_for(stitchable_project)
    workspace.prepare!

    ENV["PANORAMA_KEEP_WORKSPACE"] = "1"
    workspace.cleanup

    assert_predicate workspace.root_path, :exist?
  ensure
    ENV.delete("PANORAMA_KEEP_WORKSPACE")
    FileUtils.rm_rf(workspace.root_path) if workspace
  end
end
