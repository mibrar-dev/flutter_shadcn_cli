#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Run a disposable end-to-end CLI smoke test against the real Flutter shadcn registry.

Usage:
  tool/cli_manual_smoke.sh --registry-root /absolute/path/to/flutter_shadcn_kit/lib/registry

Options:
  --registry-root PATH   Local registry root that contains manifests/, shared/, components/.
                         Can also be provided as REAL_REGISTRY_ROOT.
  --components LIST      Space-separated component ids to install. Default: "button card alert".
  --strict-analyze       Treat flutter analyze issues as a smoke failure.
  --keep                 Keep the temporary Flutter app after the run.
  --help                 Show this help.
USAGE
}

CLI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
REGISTRY_ROOT="${REAL_REGISTRY_ROOT:-}"
COMPONENTS="button card alert"
STRICT_ANALYZE=0
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry-root)
      REGISTRY_ROOT="${2:-}"
      shift 2
      ;;
    --components)
      COMPONENTS="${2:-}"
      shift 2
      ;;
    --strict-analyze)
      STRICT_ANALYZE=1
      shift
      ;;
    --keep)
      KEEP=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$REGISTRY_ROOT" ]]; then
  candidate="$(cd "$CLI_ROOT/.." 2>/dev/null && pwd -P)/shadcn_flutter_kit/flutter_shadcn_kit/lib/registry"
  if [[ -d "$candidate" ]]; then
    REGISTRY_ROOT="$candidate"
  fi
fi

if [[ -z "$REGISTRY_ROOT" || ! -d "$REGISTRY_ROOT" ]]; then
  echo "Registry root not found. Pass --registry-root or set REAL_REGISTRY_ROOT." >&2
  exit 64
fi

for required in manifests shared components; do
  if [[ ! -d "$REGISTRY_ROOT/$required" ]]; then
    echo "Registry root is missing required folder: $REGISTRY_ROOT/$required" >&2
    exit 66
  fi
done

command -v flutter >/dev/null || {
  echo "flutter is required for this smoke test." >&2
  exit 69
}

WORK_ROOT="$(mktemp -d /tmp/flutter_shadcn_manual_smoke.XXXXXX)"
APP_ROOT="$WORK_ROOT/app"
OVERLAY_ROOT="$WORK_ROOT/source_overlay"
LOG_ROOT="$WORK_ROOT/logs"
mkdir -p "$OVERLAY_ROOT" "$LOG_ROOT"

cleanup() {
  if [[ "$KEEP" -eq 0 ]]; then
    rm -rf "$WORK_ROOT"
  else
    echo "Kept smoke workspace: $WORK_ROOT"
  fi
}
trap cleanup EXIT

ln -s "$REGISTRY_ROOT" "$OVERLAY_ROOT/registry"
ln -s "$REGISTRY_ROOT/shared" "$OVERLAY_ROOT/shared"
ln -s "$REGISTRY_ROOT/manifests" "$OVERLAY_ROOT/manifests"

run() {
  echo "==> $*"
  "$@"
}

SHADCN=(dart "$CLI_ROOT/bin/shadcn.dart")

echo "CLI root: $CLI_ROOT"
echo "Registry root: $REGISTRY_ROOT"
echo "Smoke workspace: $WORK_ROOT"

run flutter create --platforms=ios,android,web "$APP_ROOT" >"$LOG_ROOT/flutter_create.log"
cd "$APP_ROOT"

run "${SHADCN[@]}" version
run "${SHADCN[@]}" --advanced init --registry-path "$OVERLAY_ROOT/registry" --skip-integrity --yes
run "${SHADCN[@]}" --advanced list --registry-path "$OVERLAY_ROOT/registry" >"$LOG_ROOT/list.txt"
run "${SHADCN[@]}" --advanced search button --registry-path "$OVERLAY_ROOT/registry" >"$LOG_ROOT/search_button.txt"
run "${SHADCN[@]}" --advanced info button --registry-path "$OVERLAY_ROOT/registry" >"$LOG_ROOT/info_button.txt"
run "${SHADCN[@]}" --advanced dry-run button --registry-path "$OVERLAY_ROOT/registry" >"$LOG_ROOT/dry_run_button.txt"

for component in $COMPONENTS; do
  run "${SHADCN[@]}" --advanced add "$component" --registry-path "$OVERLAY_ROOT/registry"
done

run flutter pub get >"$LOG_ROOT/flutter_pub_get.log"

[[ -f .shadcn/config.json ]] || { echo "Missing .shadcn/config.json" >&2; exit 70; }
[[ -f .shadcn/state.json ]] || { echo "Missing .shadcn/state.json" >&2; exit 70; }
[[ -f shadcn.lock ]] || { echo "Missing shadcn.lock" >&2; exit 70; }
[[ -f lib/ui/shadcn/shared/theme/theme.dart ]] || {
  echo "Missing shared theme scaffold." >&2
  exit 70
}

for component in $COMPONENTS; do
  [[ -f ".shadcn/components/$component.json" ]] || {
    echo "Missing component manifest: .shadcn/components/$component.json" >&2
    exit 70
  }
done

set +e
flutter analyze >"$LOG_ROOT/flutter_analyze.log"
ANALYZE_EXIT=$?
set -e

if [[ "$ANALYZE_EXIT" -ne 0 ]]; then
  echo "flutter analyze reported issues. See: $LOG_ROOT/flutter_analyze.log" >&2
  sed -n '1,80p' "$LOG_ROOT/flutter_analyze.log" >&2
  if [[ "$STRICT_ANALYZE" -eq 1 ]]; then
    exit "$ANALYZE_EXIT"
  fi
fi

echo "Smoke passed init/add/file checks."
echo "Logs: $LOG_ROOT"
