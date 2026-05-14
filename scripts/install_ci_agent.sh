#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install the InfiniTensor local CI v2 agent on a self-hosted runner.

Usage:
  sudo .ci/scripts/install_ci_agent.sh

Environment overrides:
  CI_AGENT_SOURCE_DIR    Source .ci directory. Defaults to this script's parent .ci directory.
  CI_AGENT_INSTALL_DIR   Install directory. Defaults to /opt/infinitensor-ci.
  CI_AGENT_STATE_DIR     State directory. Defaults to /var/lib/ci-agent.
  CI_AGENT_USER          systemd service user. Defaults to CI_AGENT_RUNNER_USER.
  CI_AGENT_GROUP         Shared agent group. Defaults to ci-agent.
  CI_AGENT_RUNNER_USER   GitHub runner user to grant state-dir access. Defaults to SUDO_USER.
  CI_AGENT_POLL_INTERVAL Agent daemon poll interval in seconds. Defaults to 5.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SOURCE_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

SOURCE_DIR="${CI_AGENT_SOURCE_DIR:-${DEFAULT_SOURCE_DIR}}"
INSTALL_DIR="${CI_AGENT_INSTALL_DIR:-/opt/infinitensor-ci}"
STATE_DIR="${CI_AGENT_STATE_DIR:-/var/lib/ci-agent}"
AGENT_GROUP="${CI_AGENT_GROUP:-ci-agent}"
RUNNER_USER="${CI_AGENT_RUNNER_USER:-${SUDO_USER:-}}"
AGENT_USER="${CI_AGENT_USER:-${RUNNER_USER:-ci-agent}}"
POLL_INTERVAL="${CI_AGENT_POLL_INTERVAL:-5}"
SERVICE_FILE="/etc/systemd/system/ci-agent.service"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command '$1' not found" >&2
    exit 1
  fi
}

require_cmd python3
require_cmd systemctl
require_cmd tar

if [[ ! -f "${SOURCE_DIR}/ci_agent.py" ]]; then
  echo "error: CI_AGENT_SOURCE_DIR must point to a .ci directory with ci_agent.py: ${SOURCE_DIR}" >&2
  exit 1
fi

if ! getent group "${AGENT_GROUP}" >/dev/null; then
  groupadd --system "${AGENT_GROUP}"
fi

if ! id -u "${AGENT_USER}" >/dev/null 2>&1; then
  useradd \
    --system \
    --no-create-home \
    --home-dir "${INSTALL_DIR}" \
    --shell /usr/sbin/nologin \
    --gid "${AGENT_GROUP}" \
    "${AGENT_USER}"
fi

if [[ -n "${RUNNER_USER}" ]] && id -u "${RUNNER_USER}" >/dev/null 2>&1; then
  usermod -aG "${AGENT_GROUP}" "${RUNNER_USER}" || true
fi

systemctl stop ci-agent >/dev/null 2>&1 || true

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT

tar \
  --exclude='./.git' \
  --exclude='./__pycache__' \
  --exclude='*.pyc' \
  -C "${SOURCE_DIR}" \
  -cf - . | tar -C "${tmp_dir}" -xf -

rm -rf "${INSTALL_DIR}"
install -d -o root -g "${AGENT_GROUP}" -m 0755 "${INSTALL_DIR}"
cp -a "${tmp_dir}/." "${INSTALL_DIR}/"
chown -R root:"${AGENT_GROUP}" "${INSTALL_DIR}"
find "${INSTALL_DIR}" -type d -exec chmod 0755 {} +
find "${INSTALL_DIR}" -type f -exec chmod 0644 {} +
chmod 0755 "${INSTALL_DIR}/ci_agent.py"

install -d -o "${AGENT_USER}" -g "${AGENT_GROUP}" -m 2775 "${STATE_DIR}"
install -d -o "${AGENT_USER}" -g "${AGENT_GROUP}" -m 2775 \
  "${STATE_DIR}/tasks" \
  "${STATE_DIR}/logs" \
  "${STATE_DIR}/locks"

if [[ -n "${RUNNER_USER}" ]] && id -u "${RUNNER_USER}" >/dev/null 2>&1; then
  if command -v setfacl >/dev/null 2>&1; then
    setfacl -m "u:${RUNNER_USER}:rwx" "${STATE_DIR}" "${STATE_DIR}/tasks" "${STATE_DIR}/logs" "${STATE_DIR}/locks"
    setfacl -d -m "u:${RUNNER_USER}:rwx" "${STATE_DIR}" "${STATE_DIR}/tasks" "${STATE_DIR}/logs" "${STATE_DIR}/locks"
  else
    echo "warning: setfacl not found; ${RUNNER_USER} was added to ${AGENT_GROUP}, but runner service may need restart or relogin" >&2
  fi
fi

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=InfiniTensor local CI agent
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=${AGENT_USER}
Group=${AGENT_GROUP}
WorkingDirectory=${INSTALL_DIR}
Environment=CI_AGENT_STATE_DIR=${STATE_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/ci_agent.py --state-dir ${STATE_DIR} daemon --poll-interval ${POLL_INTERVAL}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ci-agent

echo "ci-agent installed"
echo "  source:       ${SOURCE_DIR}"
echo "  install dir:  ${INSTALL_DIR}"
echo "  state dir:    ${STATE_DIR}"
echo "  service user: ${AGENT_USER}:${AGENT_GROUP}"
if [[ -n "${RUNNER_USER}" ]]; then
  echo "  runner user:  ${RUNNER_USER}"
fi
echo
systemctl --no-pager --full status ci-agent || true
