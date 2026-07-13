# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (single-stage) built on top of the org C/C++ base image. chigraph calls
# the LLVM *C* API that clang-19 dropped, so we add the LLVM-18 dev packages + Boost as root, then
# build as `mayhem` from the full repo (incl. .git history) copied into /mayhem.
FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never an ENV — an empty ENV breaks clang). build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# Extra build deps: LLVM-18 (headers + libs + llvm-config-18) and Boost.program_options. Pin apt to
# SOURCE_DATE_EPOCH first for reproducibility when it's provided.
USER root
RUN if [ -n "$SOURCE_DATE_EPOCH" ]; then repro-sources-list.sh || true; fi; \
    apt-get update && apt-get install -yq --no-install-recommends \
      llvm-18-dev \
      clang-18 \
      libboost-dev \
      libboost-program-options-dev \
      zlib1g-dev \
      libzstd-dev \
    && rm -rf /var/lib/apt/lists/*
USER mayhem

WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
