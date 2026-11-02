#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"
MODE="${SLOP_ANALYTICS_MODE:-enforce}" # enforce | warn
WRITE_BASELINE=false

if [[ "${2:-}" == "--warn-only" ]]; then
  MODE="warn"
fi
if [[ "${2:-}" == "--write-baseline" ]]; then
  WRITE_BASELINE=true
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required." >&2
  exit 2
fi

UI_PATHS=(
  "$ROOT_DIR/XNox/App"
  "$ROOT_DIR/XNox/Features"
  "$ROOT_DIR/XNox/Shared"
)
BASELINE_FILE="$ROOT_DIR/.slop-analytics.env"

metric_count() {
  local pattern="$1"
  local matches
  matches=$(rg -n "$pattern" "${UI_PATHS[@]}" 2>/dev/null || true)
  if [[ -z "$matches" ]]; then
    echo 0
  else
    printf "%s\n" "$matches" | wc -l | tr -d ' '
  fi
}

file_count() {
  local pattern="$1"
  local files
  local matches
  files=$(rg --files "$ROOT_DIR/XNox/Features" 2>/dev/null || true)
  if [[ -z "$files" ]]; then
    echo 0
    return
  fi
  matches=$(printf "%s\n" "$files" | rg "$pattern" || true)
  if [[ -z "$matches" ]]; then
    echo 0
  else
    printf "%s\n" "$matches" | wc -l | tr -d ' '
  fi
}

pct() {
  local numerator="$1"
  local denominator="$2"
  if [[ "$denominator" -eq 0 ]]; then
    echo 0
    return
  fi
  awk -v n="$numerator" -v d="$denominator" 'BEGIN { printf "%d", (100*n)/d }'
}

clamp_0_100() {
  local value="$1"
  if [[ "$value" -lt 0 ]]; then
    echo 0
  elif [[ "$value" -gt 100 ]]; then
    echo 100
  else
    echo "$value"
  fi
}

FEATURE_VIEWS=$(file_count 'View\.swift$')
SECTION_HEADERS=$(metric_count 'SectionHeaderView\(')
CARD_SURFACES=$(metric_count '\.cardSurface\(')
INSET_SURFACES=$(metric_count '\.insetSurface\(')
HARDCODED_PADDING=$(metric_count '\.padding\((\.\w+,\s*)?[0-9]+(\.[0-9]+)?\)')
HARDCODED_CORNERS=$(metric_count 'cornerRadius:\s*[0-9]+')
SYSTEM_FONT_OVERRIDES=$(metric_count '\.font\(\.system')
GLOBAL_BG_USES=$(metric_count 'AppGradientBackground\(')
ON_TAP_GESTURES=$(metric_count '\.onTapGesture')

GENERIC_ACTIONS=$(metric_count 'Button\("(Refresh|Reload|Create|Delete|Remove|Install|Update|Close|Settings)"')
GENERIC_EMPTY_TEXT=$(metric_count 'Text\("No [^"]*"\)')
GENERIC_EMPTY_TITLES=$(metric_count 'title:\s*"No [^"]*"')
VAGUE_SUBTITLES=$(metric_count 'subtitle:\s*"[^"]*(workflow|manage|configure|quick setup|daily)[^"]*"')
GENERIC_COPY_HITS=$((GENERIC_ACTIONS + GENERIC_EMPTY_TEXT + GENERIC_EMPTY_TITLES + VAGUE_SUBTITLES))

TELEMETRY_EVENTS=$(metric_count '\b(Mixpanel|Amplitude|FirebaseAnalytics|Analytics|Telemetry)\b|\.track\(|\blogEvent\(')

TOKEN_USAGE=$((CARD_SURFACES + INSET_SURFACES))
STYLE_OVERRIDES=$((HARDCODED_PADDING + HARDCODED_CORNERS + SYSTEM_FONT_OVERRIDES))

TOKEN_ADOPTION_PCT=$(pct "$TOKEN_USAGE" $((TOKEN_USAGE + STYLE_OVERRIDES)))
STRUCTURAL_UNIFORMITY_PCT=$(pct "$SECTION_HEADERS" "$FEATURE_VIEWS")

SYSTEM_CONSISTENCY=$(clamp_0_100 $(( (TOKEN_ADOPTION_PCT * 70 + (100 - (SYSTEM_FONT_OVERRIDES * 5)) * 30) / 100 )))
VISUAL_DISTINCTIVENESS=$(clamp_0_100 $(( (100 - STRUCTURAL_UNIFORMITY_PCT / 2) - (GLOBAL_BG_USES * 8) - (SYSTEM_FONT_OVERRIDES * 2) )))
COPY_DISTINCTIVENESS=$(clamp_0_100 $((100 - (GENERIC_COPY_HITS * 4))))
if [[ "$TELEMETRY_EVENTS" -gt 0 ]]; then
  UX_OBSERVABILITY=70
else
  UX_OBSERVABILITY=20
fi

MAX_HARDCODED_PADDING="${MAX_HARDCODED_PADDING:-35}"
MAX_HARDCODED_CORNERS="${MAX_HARDCODED_CORNERS:-10}"
MAX_SYSTEM_FONT_OVERRIDES="${MAX_SYSTEM_FONT_OVERRIDES:-5}"
MAX_STRUCTURAL_UNIFORMITY_PCT="${MAX_STRUCTURAL_UNIFORMITY_PCT:-85}"
MAX_GENERIC_COPY_HITS="${MAX_GENERIC_COPY_HITS:-20}"
MIN_TELEMETRY_EVENTS="${MIN_TELEMETRY_EVENTS:-5}"

if [[ -f "$BASELINE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$BASELINE_FILE"
fi

FAILURES=0

print_offenders() {
  local title="$1"
  local pattern="$2"
  echo "  Offenders: $title"
  local lines
  lines=$(rg -n "$pattern" "${UI_PATHS[@]}" 2>/dev/null | head -n 8 || true)
  if [[ -z "$lines" ]]; then
    echo "  (none found)"
  else
    printf "%s\n" "$lines" | sed 's/^/  - /'
  fi
}

print_offenders_for_label() {
  local label="$1"
  case "$label" in
    "Hardcoded paddings")
      print_offenders "Hardcoded paddings" '\.padding\((\.\w+,\s*)?[0-9]+(\.[0-9]+)?\)'
      ;;
    "Hardcoded corner radii")
      print_offenders "Hardcoded corner radii" 'cornerRadius:\s*[0-9]+'
      ;;
    "System font overrides")
      print_offenders "System font overrides" '\.font\(\.system'
      ;;
    "Structural uniformity %")
      print_offenders "SectionHeader usage" 'SectionHeaderView\('
      ;;
    "Generic copy hits")
      print_offenders "Generic actions" 'Button\("(Refresh|Reload|Create|Delete|Remove|Install|Update|Close|Settings)"'
      print_offenders "Generic no-state text/title" 'Text\("No [^"]*"\)|title:\s*"No [^"]*"'
      ;;
    "Telemetry event hooks")
      print_offenders "Telemetry hook patterns" '\b(Mixpanel|Amplitude|FirebaseAnalytics|Analytics|Telemetry)\b|\.track\(|\blogEvent\('
      ;;
  esac
}

check_threshold() {
  local label="$1"
  local value="$2"
  local op="$3"
  local limit="$4"

  local ok=1
  if [[ "$op" == "<=" && "$value" -le "$limit" ]]; then
    ok=0
  fi
  if [[ "$op" == ">=" && "$value" -ge "$limit" ]]; then
    ok=0
  fi

  if [[ "$ok" -eq 0 ]]; then
    printf "PASS  %-32s %s %s (actual: %s)\n" "$label" "$op" "$limit" "$value"
  else
    printf "FAIL  %-32s %s %s (actual: %s)\n" "$label" "$op" "$limit" "$value"
    print_offenders_for_label "$label"
    FAILURES=$((FAILURES + 1))
  fi
}

if [[ "$WRITE_BASELINE" == "true" ]]; then
  cat >"$BASELINE_FILE" <<EOF
# Slop analytics baseline thresholds (generated).
# Ratchet these down over time.
MAX_HARDCODED_PADDING=${HARDCODED_PADDING}
MAX_HARDCODED_CORNERS=${HARDCODED_CORNERS}
MAX_SYSTEM_FONT_OVERRIDES=${SYSTEM_FONT_OVERRIDES}
MAX_STRUCTURAL_UNIFORMITY_PCT=${STRUCTURAL_UNIFORMITY_PCT}
MAX_GENERIC_COPY_HITS=${GENERIC_COPY_HITS}
MIN_TELEMETRY_EVENTS=${TELEMETRY_EVENTS}
EOF
  echo "Wrote baseline: $BASELINE_FILE"
  exit 0
fi

echo "=== Slop Analytics Report ==="
echo "Root: $ROOT_DIR"
echo
echo "Metrics"
echo "- Feature views: $FEATURE_VIEWS"
echo "- Section headers: $SECTION_HEADERS"
echo "- cardSurface uses: $CARD_SURFACES"
echo "- insetSurface uses: $INSET_SURFACES"
echo "- Hardcoded paddings: $HARDCODED_PADDING"
echo "- Hardcoded corner radii: $HARDCODED_CORNERS"
echo "- .font(.system...) overrides: $SYSTEM_FONT_OVERRIDES"
echo "- AppGradientBackground uses: $GLOBAL_BG_USES"
echo "- onTapGesture uses: $ON_TAP_GESTURES"
echo "- Generic copy hits: $GENERIC_COPY_HITS"
echo "- Telemetry event hooks: $TELEMETRY_EVENTS"
echo
echo "Scorecard"
echo "- System consistency: ${SYSTEM_CONSISTENCY}/100"
echo "- Visual distinctiveness: ${VISUAL_DISTINCTIVENESS}/100"
echo "- Copy distinctiveness: ${COPY_DISTINCTIVENESS}/100"
echo "- UX observability: ${UX_OBSERVABILITY}/100"
echo
echo "Threshold checks"
check_threshold "Hardcoded paddings" "$HARDCODED_PADDING" "<=" "$MAX_HARDCODED_PADDING"
check_threshold "Hardcoded corner radii" "$HARDCODED_CORNERS" "<=" "$MAX_HARDCODED_CORNERS"
check_threshold "System font overrides" "$SYSTEM_FONT_OVERRIDES" "<=" "$MAX_SYSTEM_FONT_OVERRIDES"
check_threshold "Structural uniformity %" "$STRUCTURAL_UNIFORMITY_PCT" "<=" "$MAX_STRUCTURAL_UNIFORMITY_PCT"
check_threshold "Generic copy hits" "$GENERIC_COPY_HITS" "<=" "$MAX_GENERIC_COPY_HITS"
check_threshold "Telemetry event hooks" "$TELEMETRY_EVENTS" ">=" "$MIN_TELEMETRY_EVENTS"
echo

if [[ "$FAILURES" -gt 0 ]]; then
  echo "Result: $FAILURES threshold check(s) failed."
  if [[ "$MODE" == "enforce" ]]; then
    exit 1
  fi
  echo "Mode is warn-only; returning success."
else
  echo "Result: all threshold checks passed."
fi
