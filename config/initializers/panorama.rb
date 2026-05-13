# Selects the stitching engine used by StitchPanoramaJob.
#
# Default is FakePanoramaStitcher so tests and a fresh `bin/setup` always work
# without external dependencies. Opt in to the real engine by setting
#
#   PANORAMA_STITCHER=HuginPanoramaStitcher
#
# in your shell or .env.development.local, after running `bin/panorama-hugin-build`.
Rails.application.config.panorama_stitcher_class =
  ENV.fetch("PANORAMA_STITCHER", "FakePanoramaStitcher")
