# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image
# (ghcr.io/savantenvs/base), which already provides debian + clang/llvm + libFuzzer +
# the non-root identities + the build contract ENV (CC/CXX/LIB_FUZZING_ENGINE/
# STANDALONE_FUZZ_MAIN/SANITIZER_FLAGS/SRC).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mruby-commit:test .

FROM ghcr.io/savantenvs/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV): an empty ENV value breaks clang.
ARG SOURCE_DATE_EPOCH
# Sanitizer override (undefaulted so the base ENV flows through when not passed).
ARG SANITIZER_FLAGS
# Coverage instrumentation for the TEST build only (empty = off).
ARG COVERAGE_FLAGS=
# Build parallelism (build.sh falls back to nproc when empty).
ARG MAYHEM_JOBS=

# mruby's build system is rake-driven, so the image needs a host ruby + rake. bison is
# already in the base (mruby generates its parser from parse.y). Installed HERE (as root,
# at image-build time) — never from build.sh — so that mayhem/build.sh stays air-gapped
# and can be re-run offline (SPEC §6.5).
USER root
RUN if [ -n "$SOURCE_DATE_EPOCH" ]; then repro-sources-list.sh || true ; fi ; \
    apt-get update && apt-get install -yq --no-install-recommends \
      ruby ruby-dev rake \
 && rm -rf /var/lib/apt/lists/*
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git
# history) is copied to /mayhem; build.sh builds in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# mruby's compiler gem vendors Prism as a GIT SUBMODULE (mrbgems/mruby-compiler/lib/prism) and its
# mrbgem.rake fetches it on demand. CI checks out with `submodules: recursive`, but a plain clone of
# the branch does not — so populate it HERE (image build, network still available) and let
# mayhem/build.sh stay air-gapped: with the submodule in place rake's prism_submodule task is a no-op
# and the offline build.sh re-run never reaches for the network (SPEC §6.5).
RUN if [ ! -f mrbgems/mruby-compiler/lib/prism/templates/template.rb ]; then \
      git submodule update --init mrbgems/mruby-compiler/lib/prism ; \
    fi

RUN bash mayhem/build.sh

# Run the project's functional tests at build time (a failing suite fails the image build).
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
