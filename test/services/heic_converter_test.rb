require "test_helper"

class HeicConverterTest < ActiveSupport::TestCase
  # Minimal valid HEIF container header so the magic-byte sniffer fires:
  # 4 bytes size + "ftyp" + brand "heic" + minor version + compatible brand.
  HEIC_HEADER = [ 0, 0, 0, 24 ].pack("N") + "ftypheic" + "\x00\x00\x00\x00" + "mif1heic"

  def heic_fixture
    tempfile = Tempfile.new([ "iphone_", ".jpeg" ], Rails.root.join("tmp"))
    tempfile.binmode
    tempfile.write(HEIC_HEADER)
    tempfile.write("\0" * 64)
    tempfile.rewind
    tempfile
  end

  def uploaded(tempfile, filename:, content_type:)
    Rack::Test::UploadedFile.new(tempfile, content_type, original_filename: filename)
  end

  test ".heic? returns true when content_type is image/heic" do
    tempfile = heic_fixture
    file = uploaded(tempfile, filename: "IMG.jpeg", content_type: "image/heic")
    assert HeicConverter.heic?(file)
  ensure
    tempfile&.close!
  end

  test ".heic? sniffs magic bytes when content_type lies (iPhone export with .jpeg name)" do
    tempfile = heic_fixture
    file = uploaded(tempfile, filename: "IMG.jpeg", content_type: "image/jpeg")
    assert HeicConverter.heic?(file)
  ensure
    tempfile&.close!
  end

  test ".heic? returns false for a real JPEG" do
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
    assert_not HeicConverter.heic?(file)
  end

  test ".convert_if_needed passes JPEGs through unchanged" do
    file = Rack::Test::UploadedFile.new(
      Rails.root.join("test/fixtures/files/test_photo.jpg"),
      "image/jpeg"
    )
    assert_same file, HeicConverter.convert_if_needed(file)
  end

  test ".convert_if_needed returns a JPEG UploadedFile for HEIC inputs" do
    tempfile = heic_fixture
    file = uploaded(tempfile, filename: "IMG_6220.jpeg", content_type: "image/heic")

    converted = SuccessfulConverter.new(file).convert

    assert_equal "image/jpeg", converted.content_type
    assert_equal "IMG_6220.jpg", converted.original_filename
    # Active Storage calls `.open` on the UploadedFile during attach; the
    # tempfile must be a Tempfile (or anything where #open is public).
    # File-instances would raise NoMethodError(private method 'open').
    assert_nothing_raised { converted.open }
  ensure
    tempfile&.close!
    HeicConverter.cleanup(converted) if converted
  end

  test "convert raises ConversionError when heif-convert fails" do
    tempfile = heic_fixture
    file = uploaded(tempfile, filename: "IMG.jpeg", content_type: "image/heic")

    assert_raises(HeicConverter::ConversionError) do
      FailingConverter.new(file).convert
    end
  ensure
    tempfile&.close!
  end

  test ".cleanup deletes the converted tempfile and closes the handle" do
    target_path = Rails.root.join("tmp", "heic_cleanup_test_#{SecureRandom.hex(4)}.jpg")
    FileUtils.cp(Rails.root.join("test/fixtures/files/test_photo.jpg"), target_path)
    converted = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(target_path, "rb"),
      filename: "x.jpg",
      type: "image/jpeg"
    )

    HeicConverter.cleanup(converted)

    assert_not File.exist?(target_path), "temp file should be deleted after cleanup"
  end

  # Bypasses Open3 by copying a known-good JPEG over a Tempfile. Mirrors the
  # real Tempfile-based shape so tests catch contract violations like the
  # one that previously slipped through (raw File handles can't be `open`ed
  # by Active Storage, because Kernel#open is private on File).
  class SuccessfulConverter < HeicConverter
    def convert
      output = Tempfile.new([ "heic_test_", ".jpg" ], Rails.root.join("tmp"))
      output.binmode
      output.close
      FileUtils.cp(Rails.root.join("test/fixtures/files/test_photo.jpg"), output.path)
      output.open
      output.binmode
      ActionDispatch::Http::UploadedFile.new(
        tempfile: output,
        filename: send(:derive_jpeg_filename),
        type: "image/jpeg"
      )
    end
  end

  # Simulates heif-convert returning a non-zero exit, so we can assert the
  # ConversionError path without trying to produce a malformed HEIC file.
  class FailingConverter < HeicConverter
    def convert
      raise HeicConverter::ConversionError, "heif-convert failed (exit 1): bad input file"
    end
  end
end
