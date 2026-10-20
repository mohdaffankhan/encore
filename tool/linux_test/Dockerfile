# Linux test environment for Encore: builds the Linux app and runs the
# integration tests under a virtual display, with a dummy sound card so
# playback is exercised for real. See tool/linux_test/run.sh.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git curl unzip xz-utils zip rsync \
      build-essential clang cmake ninja-build pkg-config libgtk-3-dev libmpv-dev \
      xvfb xauth libgl1-mesa-dri libegl1 pulseaudio dbus-x11 \
      fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.47.7
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-linux-desktop \
    && flutter precache --linux

WORKDIR /work
COPY run.sh /run.sh
RUN chmod +x /run.sh
ENTRYPOINT ["/run.sh"]
