# Vacation Station 14 — custom MapServer image
#
# Upstream ghcr.io/space-wizards/ss14.mapserver ships dotnet SDK 9; our
# repo's global.json pins dotnet 10, so Content.MapRenderer won't build
# inside the vanilla image. This Dockerfile layers the 10.0 SDK on top.
#
# Used from ops/observability/docker-compose.yml:
#
#   mapserver:
#     build:
#       context: ../mapserver
#       dockerfile: Dockerfile

FROM ghcr.io/space-wizards/ss14.mapserver:latest

USER root

# Install dotnet 10 SDK side-by-side with the existing 9.0 install.
# Microsoft publish an install script; we pin to the 10.0 STS channel
# so picks up latest 10.0.x patches automatically on rebuild.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
 && bash /tmp/dotnet-install.sh --channel 10.0 --install-dir /usr/share/dotnet \
 && rm /tmp/dotnet-install.sh

# The dotnet binary already lives at /usr/share/dotnet/dotnet from the
# base image (for 9); the install script above writes alongside it so
# both SDKs are visible.
RUN /usr/share/dotnet/dotnet --list-sdks

# Back to the non-root UID the upstream image uses
USER 20202:20202
