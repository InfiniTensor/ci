#!/usr/bin/env bash
set -euo pipefail

# Seed xmake package cache from /opt/third_party_cache so `xmake require`
# does not re-download pybind11 from GitHub during `xmake f` / build.
PYBIND11_VERSION="${PYBIND11_VERSION:-v3.0.4}"
ZIP_SRC="/opt/third_party_cache/xmake_pkg_search/${PYBIND11_VERSION}.zip"
PKG_MONTH="$(date +%y%m)"
PKG_DIR="/root/.xmake/cache/packages/${PKG_MONTH}/p/pybind11/${PYBIND11_VERSION}"

if [[ ! -f "${ZIP_SRC}" ]]; then
  echo "install_xmake_pybind11: missing ${ZIP_SRC}" >&2
  exit 1
fi

mkdir -p "${PKG_DIR}"
# xmake cachedir searchnames: v3.0.4.zip, pybind11-v3.0.4.zip, pybind11-3.0.4.zip
cp -a "${ZIP_SRC}" "${PKG_DIR}/${PYBIND11_VERSION}.zip"

xmake require -y "pybind11 ${PYBIND11_VERSION}"
