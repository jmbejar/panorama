class SourcePhoto < ApplicationRecord
  belongs_to :panorama_project
  has_one_attached :image

  validates :position, presence: true, uniqueness: { scope: :panorama_project_id }

  scope :ordered, -> { order(:position) }

  def populate_metadata_from_blob!
    return unless image.attached?

    blob = image.blob
    blob.analyze unless blob.analyzed?

    update!(
      filename: blob.filename.to_s,
      content_type: blob.content_type,
      file_size: blob.byte_size,
      width: blob.metadata["width"],
      height: blob.metadata["height"]
    )
  end
end
