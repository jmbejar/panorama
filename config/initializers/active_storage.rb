# Use MiniMagick (ImageMagick) for Active Storage analysis and variant processing.
# Rails 8 defaults the variant processor to :vips and lists Vips first in analyzers,
# but libvips isn't a required dependency of this app. Hugin / ImageMagick / exiftool
# are already part of the stitching pipeline, so MiniMagick is what we actually have
# installed in every environment.
Rails.application.config.active_storage.variant_processor = :mini_magick

Rails.application.config.after_initialize do
  ActiveStorage.analyzers.delete(ActiveStorage::Analyzer::ImageAnalyzer::Vips)
end
