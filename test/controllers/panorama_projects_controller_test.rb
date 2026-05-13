require "test_helper"

class PanoramaProjectsControllerTest < ActionDispatch::IntegrationTest
  def uploaded_file
    Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
  end

  test "index renders" do
    get panorama_projects_path
    assert_response :success
    assert_select "h1", "Panorama projects"
  end

  test "index empty state shows when no projects exist" do
    PanoramaProject.destroy_all
    get panorama_projects_path
    assert_response :success
    assert_select "h2", "No projects yet"
  end

  test "new renders form with capture guidance copy" do
    get new_panorama_project_path
    assert_response :success
    assert_select "h2", "How to capture better 360 photos"
    assert_select "input[type=text][name='panorama_project[title]']"
    assert_select "input[type=file][name='panorama_project[photos][]'][multiple=multiple]"
  end

  test "create with title and photos creates project, attaches photos, transitions to uploaded" do
    assert_difference -> { PanoramaProject.count }, 1 do
      assert_difference -> { SourcePhoto.count }, 2 do
        post panorama_projects_path, params: {
          panorama_project: { title: "From controller", photos: [ uploaded_file, uploaded_file ] }
        }
      end
    end

    project = PanoramaProject.last
    assert_equal "From controller", project.title
    assert_equal "uploaded", project.status
    assert_equal 2, project.source_photos.count
    assert_redirected_to project
  end

  test "create with title and no photos creates a draft" do
    assert_difference -> { PanoramaProject.count }, 1 do
      post panorama_projects_path, params: {
        panorama_project: { title: "Title only" }
      }
    end

    project = PanoramaProject.last
    assert_equal "draft", project.status
    assert_equal 0, project.source_photos.count
    assert_redirected_to project
  end

  test "create without title re-renders new with 422" do
    assert_no_difference -> { PanoramaProject.count } do
      post panorama_projects_path, params: { panorama_project: { title: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "h2", "How to capture better 360 photos"
  end

  test "show renders project metadata and thumbnails" do
    project = PanoramaProject.create!(title: "Visible")
    project.attach_photos([ uploaded_file ])

    get panorama_project_path(project)

    assert_response :success
    assert_select "h1", "Visible"
    assert_select "img"
  end

  test "show renders for a project with no photos" do
    project = panorama_projects(:draft_project)
    get panorama_project_path(project)
    assert_response :success
    assert_match "No photos uploaded", response.body
  end

  test "destroy removes the project" do
    project = panorama_projects(:draft_project)
    assert_difference -> { PanoramaProject.count }, -1 do
      delete panorama_project_path(project)
    end
    assert_redirected_to panorama_projects_path
  end
end
