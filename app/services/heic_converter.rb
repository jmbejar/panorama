require "open3"
require "securerandom"

# Pre-converts iPhone HEIC photos to JPEG at upload time. Every downstream
# consumer (Active Storage variants, Hugin's pto_gen/cpfind, EXIF readers)
# either has no HEIC delegate at all (ImageMagick on Debian) or chokes on
# iPhone HEIC metadata (libvips 8.14 + libheif 1.15). Converting upstream
# sidesteps the problem and produces a format every tool reliably handles.
class HeicConverter
  HEIC_CONTENT_TYPES = %w[image/heic image/heif].freeze
  # Magic-byte ftyp brands that identify HEIF container files. Browsers
  # commonly send `image/jpeg` for files whose extension is .jpeg but whose
  # actual bytes start with one of these brands.
  HEIC_FTYP_BRANDS = %w[heic heix hevc hevx heim heis hevm hevs mif1 msf1].freeze

  CONVERTER = ENV.fetch("HEIF_CONVERT_PATH", "heif-convert").freeze
  JPEG_QUALITY = 90

  class ConversionError < StandardError; end

  def self.heic?(file)
    return false unless file.respond_to?(:path) && file.path
    declared = file.respond_to?(:content_type) ? file.content_type.to_s.downcase : ""
    return true if HEIC_CONTENT_TYPES.include?(declared)
    sniff_ftyp(file.path)
  end

  def self.sniff_ftyp(path)
    return false unless File.file?(path)
    header = File.open(path, "rb") { |io| io.read(12).to_s }
    return false if header.length < 12 || header[4, 4] != "ftyp"
    HEIC_FTYP_BRANDS.include?(header[8, 4])
  end

  # Returns either the original `uploaded_file` or, if it's HEIC, a JPEG
  # ActionDispatch::Http::UploadedFile that can be passed straight to
  # `image.attach`. The caller owns cleanup of any converted temp file —
  # call `.cleanup(file)` after Active Storage has copied the bytes.
  def self.convert_if_needed(uploaded_file)
    return uploaded_file unless heic?(uploaded_file)
    new(uploaded_file).convert
  end

  def self.cleanup(converted_file)
    return unless converted_file.respond_to?(:tempfile)
    tempfile = converted_file.tempfile
    # Tempfile#close! closes AND unlinks; falls back to manual cleanup for
    # any other IO-like object (used by tests that pass plain Files).
    if tempfile.respond_to?(:close!)
      tempfile.close!
    else
      path = tempfile.path
      tempfile.close rescue nil
      File.delete(path) if path && File.exist?(path)
    end
  end

  def initialize(uploaded_file)
    @uploaded_file = uploaded_file
  end

  def convert
    # Tempfile (not raw File) is required because Active Storage's attach
    # path calls `tempfile.open` — that's a public method on Tempfile but
    # private (Kernel#open) on File. Close before the shell-out so
    # heif-convert can write to the path, then reopen for the read.
    output = Tempfile.new([ "heic_converted_", ".jpg" ], Rails.root.join("tmp"))
    output.binmode
    output.close

    stdout, stderr, status = Open3.capture3(
      CONVERTER, "--quality", JPEG_QUALITY.to_s, @uploaded_file.path, output.path
    )

    unless status.success? && File.size?(output.path).to_i.positive?
      output.close! rescue nil
      raise ConversionError, "heif-convert failed (exit #{status.exitstatus}): #{stderr.presence || stdout}"
    end

    output.open
    output.binmode

    ActionDispatch::Http::UploadedFile.new(
      tempfile: output,
      filename: derive_jpeg_filename,
      type: "image/jpeg"
    )
  end

  private

  def derive_jpeg_filename
    original = @uploaded_file.respond_to?(:original_filename) ? @uploaded_file.original_filename.to_s : ""
    base = File.basename(original, ".*").presence || "photo"
    "#{base}.jpg"
  end
end
