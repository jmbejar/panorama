require "test_helper"

class StitchingResultTest < ActiveSupport::TestCase
  test "success factory marks the result as successful" do
    result = StitchingResult.success(image_path: "/tmp/p.jpg", engine: "fake", stdout: "ok")

    assert result.success?
    assert_not result.failure?
    assert_equal "/tmp/p.jpg", result.image_path.to_s
    assert_equal "fake", result.engine
    assert_equal 0, result.exit_code
    assert_nil result.error_message
  end

  test "failure factory marks the result as failed" do
    result = StitchingResult.failure(engine: "fake", error_message: "boom", stderr: "details")

    assert result.failure?
    assert_not result.success?
    assert_equal "boom", result.error_message
    assert_equal 1, result.exit_code
    assert_equal "details", result.stderr
  end

  test "combined_logs concatenates stdout and stderr" do
    result = StitchingResult.success(image_path: "/x", engine: "e", stdout: "out", stderr: "err")

    assert_includes result.combined_logs, "[stdout]"
    assert_includes result.combined_logs, "out"
    assert_includes result.combined_logs, "[stderr]"
    assert_includes result.combined_logs, "err"
  end
end
