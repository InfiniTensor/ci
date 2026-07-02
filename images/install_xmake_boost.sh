#!/usr/bin/env bash
set -euo pipefail

# Seed xmake package cache from /opt/third_party_cache so `xmake require`
# does not re-download boost from GitHub during `xmake f` / build.
BOOST_VERSION="${BOOST_VERSION:-1.90.0}"
ARCHIVE_NAME="boost-${BOOST_VERSION}-cmake.tar.gz"
ARCHIVE_SRC="/opt/third_party_cache/xmake_pkg_search/${ARCHIVE_NAME}"
PKG_MONTH="$(date +%y%m)"
PKG_DIR="/root/.xmake/cache/packages/${PKG_MONTH}/b/boost/${BOOST_VERSION}"

if [[ ! -f "${ARCHIVE_SRC}" ]]; then
  echo "install_xmake_boost: missing ${ARCHIVE_SRC}" >&2
  exit 1
fi

mkdir -p "${PKG_DIR}"
# xmake cachedir searchnames for boost cmake build (default for >= 1.86)
cp -a "${ARCHIVE_SRC}" "${PKG_DIR}/${ARCHIVE_NAME}"
cp -a "${ARCHIVE_SRC}" "${PKG_DIR}/boost-${BOOST_VERSION}.tar.gz"

xmake g --pkg_searchdirs=/opt/third_party_cache/xmake_pkg_search
xmake require -y --extra="{configs={stacktrace=true}}" "boost ${BOOST_VERSION}"
