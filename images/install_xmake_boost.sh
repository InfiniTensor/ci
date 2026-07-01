#!/usr/bin/env bash
set -euo pipefail

# Point xmake at pre-downloaded boost archives so runtime fetches skip GitHub.
BOOST_VERSION="${BOOST_VERSION:-1.90.0}"
TARBALL="boost-${BOOST_VERSION}-b2-nodocs.tar.gz"
TARBALL_SRC="/opt/third_party_cache/xmake_pkg_search/${TARBALL}"
SEARCH_DIR="/opt/third_party_cache/xmake_pkg_search"

if [[ ! -f "${TARBALL_SRC}" ]]; then
  echo "install_xmake_boost: missing ${TARBALL_SRC}" >&2
  exit 1
fi

xmake g --pkg_searchdirs="${SEARCH_DIR}"
