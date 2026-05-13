class PanoramaProject < ApplicationRecord
  STATUSES = %w[draft uploaded validating ready_to_process processing completed failed].freeze

  enum :status, STATUSES.index_by(&:itself), validate: true

  has_many :source_photos, -> { order(:position) }, dependent: :destroy
  has_one_attached :final_panorama_image

  validates :title, presence: true, length: { maximum: 200 }

  # Not wrapped in a transaction: Active Storage uploads files in an after_commit
  # callback (see ActiveStorage::Attached::Model), so wrapping these calls in an
  # outer transaction defers the actual disk upload past the analyze step and
  # populate_metadata_from_blob! fails with FileNotFoundError. Partial state on
  # failure is acceptable here — Phase 5 validation surfaces broken uploads.
  def attach_photos(uploaded_files)
    files = Array(uploaded_files).compact_blank
    return if files.empty?

    next_position = (source_photos.maximum(:position) || 0) + 1
    files.each_with_index do |file, idx|
      photo = source_photos.create!(position: next_position + idx)
      photo.image.attach(file)
      photo.populate_metadata_from_blob!
    end
    uploaded! if draft?
  end
end
