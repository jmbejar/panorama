# Stitching image used by HuginPanoramaStitcher. Built locally; not pushed.
# Build: bin/panorama-hugin-build
# Tag:   panorama-hugin:latest

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        hugin-tools \
        enblend \
        imagemagick \
        libimage-exiftool-perl \
    && rm -rf /var/lib/apt/lists/*

# ImageMagick on Debian disables some delegates by default; allow JPEG/TIFF
# conversion that the stitch script does at the end.
RUN sed -i \
    -e 's|rights="none" pattern="JPEG"|rights="read|write" pattern="JPEG"|' \
    -e 's|rights="none" pattern="TIFF"|rights="read|write" pattern="TIFF"|' \
    /etc/ImageMagick-6/policy.xml || true

COPY stitch.sh /usr/local/bin/stitch.sh
RUN chmod +x /usr/local/bin/stitch.sh

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/stitch.sh"]
