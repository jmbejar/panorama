module PanoramaProjectsHelper
  STATUS_BADGE_CLASSES = {
    "draft"             => "bg-gray-100 text-gray-800",
    "uploaded"          => "bg-blue-100 text-blue-800",
    "validating"        => "bg-blue-100 text-blue-800",
    "ready_to_process"  => "bg-blue-100 text-blue-800",
    "processing"        => "bg-amber-100 text-amber-800",
    "completed"         => "bg-green-100 text-green-800",
    "failed"            => "bg-red-100 text-red-800"
  }.freeze

  def status_badge_classes(status)
    STATUS_BADGE_CLASSES.fetch(status.to_s, "bg-gray-100 text-gray-800")
  end

  def human_file_size(bytes)
    return "—" if bytes.blank?
    ActiveSupport::NumberHelper.number_to_human_size(bytes)
  end

  # Whether to render developer-only diagnostics like raw stitcher logs.
  # Always on in development; opt-in elsewhere via ?debug=1 so we can ask a
  # production user to grab logs without exposing stderr to everyone.
  def developer_debug?(_panorama_project = nil)
    Rails.env.development? || params[:debug].present?
  end
end
