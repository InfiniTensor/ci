#!/usr/bin/env bash
set -euo pipefail

# Install pybind11 into the xmake package store from /opt/third_party_cache,
# avoiding GitHub downloads during xmake f / build.
PYBIND11_VERSION="${PYBIND11_VERSION:-v3.0.4}"
CACHE_SRC="/opt/third_party_cache/pybind11"
PKG_MONTH="$(date +%y%m)"
PKG_DIR="/root/.xmake/cache/packages/${PKG_MONTH}/p/pybind11/${PYBIND11_VERSION}"

if [[ ! -f "${CACHE_SRC}/CMakeLists.txt" ]]; then
  echo "install_xmake_pybind11: missing ${CACHE_SRC}/CMakeLists.txt" >&2
  exit 1
fi

mkdir -p "${PKG_DIR}/source"
rm -rf "${PKG_DIR}/source/pybind11"
cp -a "${CACHE_SRC}" "${PKG_DIR}/source/pybind11"
test -f "${PKG_DIR}/source/pybind11/CMakeLists.txt"

xmake require -y "pybind11 ${PYBIND11_VERSION}"
