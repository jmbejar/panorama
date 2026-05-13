# Selects the stitching engine used by StitchPanoramaJob.
# Phase 2 uses FakePanoramaStitcher (deterministic placeholder output).
# Phase 3 will swap this for HuginPanoramaStitcher.
Rails.application.config.panorama_stitcher_class = "FakePanoramaStitcher"
