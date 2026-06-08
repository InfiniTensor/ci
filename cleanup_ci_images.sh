#!/usr/bin/env bash
# Delete local CI Docker images, keeping only the newest KEEP_COUNT per repository prefix.
# Targets: infinilm-ci/<platform>, infiniops-ci/<platform>
#
# Usage:
#   ./scripts/cleanup_ci_images.sh --platform nvidia
#   ./scripts/cleanup_ci_images.sh --platform metax --dry-run
#   ./scripts/cleanup_ci_images.sh --platform nvidia --count 5
#
# Scheduled via GitHub Actions: .github/workflows/cleanup_ci_images.yml
# Manual run: Actions -> "Cleanup CI Docker Images" -> "Run workflow"

set -euo pipefail

KEEP_COUNT=5
DRY_RUN=false
PLATFORM=""

usage() {
  cat <<'EOF'
Usage: cleanup_ci_images.sh --platform PLATFORM [OPTIONS]

Remove local CI Docker images, keeping only the newest N images per repository prefix.

Options:
  --platform P  Platform name, e.g. nvidia, metax, moore, cambricon, iluvatar, ascend (required)
  --count N     Keep the newest N images; delete older ones (default: 5)
  --dry-run     List images that would be deleted without removing them
  -h, --help    Show this help message
EOF
}

log() {
  printf '[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$*"
}

image_created_epoch() {
  local image_id="$1"
  local created_at="$2"
  local epoch=""

  if [[ -n "${created_at}" ]]; then
    epoch=$(date -d "${created_at% UTC}" +%s 2>/dev/null) \
      || epoch=$(date -d "${created_at}" +%s 2>/dev/null) \
      || true
  fi

  if [[ -z "${epoch}" ]]; then
    local inspect_created
    inspect_created=$(docker inspect --format '{{.Created}}' "${image_id}" 2>/dev/null) || return 1
    epoch=$(date -d "${inspect_created}" +%s 2>/dev/null) || return 1
  fi

  printf '%s' "${epoch}"
}

image_display_name() {
  local image_id="$1"
  local repository="$2"
  local tag="$3"

  if [[ -n "${repository}" && -n "${tag}" && "${tag}" != "<none>" ]]; then
    printf '%s:%s' "${repository}" "${tag}"
  else
    printf '%s' "${image_id}"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform)
      PLATFORM="${2:?--platform requires a name}"
      shift 2
      ;;
    --count)
      KEEP_COUNT="${2:?--count requires a number}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${PLATFORM}" ]]; then
  echo "Error: --platform is required (e.g. nvidia, metax)" >&2
  usage >&2
  exit 1
fi

if ! [[ "${PLATFORM}" =~ ^[a-z0-9_-]+$ ]]; then
  echo "Error: invalid platform name: ${PLATFORM}" >&2
  exit 1
fi

IMAGE_PREFIXES=(
  "infinilm-ci/${PLATFORM}"
  "infiniops-ci/${PLATFORM}"
)

if ! [[ "$KEEP_COUNT" =~ ^[0-9]+$ ]] || [[ "$KEEP_COUNT" -lt 1 ]]; then
  echo "Error: --count must be a positive integer" >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker not found in PATH" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Error: cannot connect to Docker daemon" >&2
  exit 1
fi

deleted=0
failed=0
kept=0

log "Platform: ${PLATFORM}; keep newest ${KEEP_COUNT} image(s) per prefix"
if $DRY_RUN; then
  log "Dry-run mode: no images will be removed"
fi

for prefix in "${IMAGE_PREFIXES[@]}"; do
  log "Scanning ${prefix}:*"

  tmpfile=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '${tmpfile}'" EXIT

  while IFS='|' read -r image_id repository tag created_at; do
    [[ -z "${image_id}" ]] && continue
    [[ "${tag}" == "<none>" ]] && continue

    created_epoch=$(image_created_epoch "${image_id}" "${created_at}") || {
      log "WARN: skip $(image_display_name "${image_id}" "${repository}" "${tag}") (cannot determine created time)"
      ((failed++)) || true
      continue
    }

    printf '%s|%s|%s|%s|%s\n' \
      "${created_epoch}" "${image_id}" "${repository}" "${tag}" "${created_at}"
  done < <(
    docker images \
      --format '{{.ID}}|{{.Repository}}|{{.Tag}}|{{.CreatedAt}}' \
      --filter "reference=${prefix}"
  ) >"${tmpfile}"

  total=$(wc -l <"${tmpfile}" | tr -d ' ')
  if [[ "${total}" -eq 0 ]]; then
    log "No images found for ${prefix}"
    rm -f "${tmpfile}"
    trap - EXIT
    continue
  fi

  rank=0
  while IFS='|' read -r created_epoch image_id repository tag created_at; do
    ((rank++)) || true
    name=$(image_display_name "${image_id}" "${repository}" "${tag}")

    if ((rank <= KEEP_COUNT)); then
      log "KEEP ${name} (rank ${rank}/${total}, created ${created_at:-unknown})"
      ((kept++)) || true
      continue
    fi

    if $DRY_RUN; then
      log "WOULD DELETE ${name} (rank ${rank}/${total}, created ${created_at:-unknown})"
      ((deleted++)) || true
      continue
    fi

    docker rmi "${name}"
    if docker rmi -f "${image_id}" >/dev/null 2>&1; then
      log "Deleted ${name} (rank ${rank}/${total}, created ${created_at:-unknown})"
      ((deleted++)) || true
    else
      log "WARN: failed to delete ${name} (image may be in use)"
      ((failed++)) || true
    fi
  done < <(sort -t'|' -k1,1nr "${tmpfile}")

  rm -f "${tmpfile}"
  trap - EXIT
done

log "Done. removed=${deleted} kept=${kept} failed=${failed}"
