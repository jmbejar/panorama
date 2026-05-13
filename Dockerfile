# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t panorama .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name panorama panorama

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages. Hugin tools (hugin-tools, enblend, imagemagick,
# libimage-exiftool-perl) are baked into the same image so the Rails app can
# invoke /usr/local/bin/stitch.sh directly via LocalHuginPanoramaStitcher —
# no docker-in-docker, which is what makes this image deployable on Fly.io.
# libheif 1.15 (bookworm) errors on modern iPhone HEIC ("Metadata not
# correctly assigned"); bookworm-backports ships 1.19 which decodes those
# files correctly. Enable backports just for libheif so the rest of the
# image stays on bookworm's stable channel.
RUN echo "deb http://deb.debian.org/debian bookworm-backports main" \
        > /etc/apt/sources.list.d/backports.list && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl libjemalloc2 libvips sqlite3 \
        hugin-tools enblend imagemagick libimage-exiftool-perl && \
    apt-get install --no-install-recommends -y -t bookworm-backports \
        libheif1 libheif-examples && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# ImageMagick on Debian disables JPEG/TIFF delegates by default and caps area
# at 128 MP — both bite the stitch.sh tif→jpg step on real panoramas. Relax
# the policy. Uses `#` as the sed delimiter since `|` appears in replacements.
RUN for policy in /etc/ImageMagick-6/policy.xml /etc/ImageMagick-7/policy.xml; do \
        if [ -f "$policy" ]; then \
            sed -i \
                -e 's#rights="none" pattern="JPEG"#rights="read|write" pattern="JPEG"#' \
                -e 's#rights="none" pattern="TIFF"#rights="read|write" pattern="TIFF"#' \
                -e 's#name="memory" value="[^"]*"#name="memory" value="1GiB"#' \
                -e 's#name="area" value="[^"]*"#name="area" value="1GP"#' \
                -e 's#name="width" value="[^"]*"#name="width" value="64KP"#' \
                -e 's#name="height" value="[^"]*"#name="height" value="64KP"#' \
                -e 's#name="map" value="[^"]*"#name="map" value="2GiB"#' \
                -e 's#name="disk" value="[^"]*"#name="disk" value="8GiB"#' \
                "$policy"; \
        fi; \
    done

# Stitch script lives at a stable path; LocalHuginPanoramaStitcher invokes it
# via Open3 with WORKSPACE set. Same script as docker/hugin/Dockerfile copies
# in for the local-dev Docker-based stitcher.
COPY docker/hugin/stitch.sh /usr/local/bin/stitch.sh
RUN chmod +x /usr/local/bin/stitch.sh

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile




# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
