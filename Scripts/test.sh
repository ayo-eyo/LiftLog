#!/usr/bin/env bash
#
# Запуск тестов LiftLog в симуляторе.
#
#   Scripts/test.sh                # план Unit (быстрый, только юнит-тесты)
#   Scripts/test.sh All            # план All (юнит + UI)
#   Scripts/test.sh Unit "iPhone Air"
#
# Переменные окружения:
#   DESTINATION — полностью переопределяет -destination
#   RESULT_BUNDLE — путь для .xcresult (по умолчанию build/TestResults.xcresult)

set -euo pipefail

cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

PLAN="${1:-Unit}"
DEVICE="${2:-}"
RESULT_BUNDLE="${RESULT_BUNDLE:-build/TestResults.xcresult}"

if [[ -z "${DESTINATION:-}" ]]; then
  if [[ -z "$DEVICE" ]]; then
    # Первый доступный iPhone-симулятор, чтобы скрипт не ломался при смене Xcode.
    DEVICE=$(xcrun simctl list devices available | grep -oE '^ +iPhone [^(]+' | head -1 | sed 's/^ *//;s/ *$//')
  fi
  if [[ -z "$DEVICE" ]]; then
    echo "Не найден ни один доступный iPhone-симулятор" >&2
    exit 1
  fi
  DESTINATION="platform=iOS Simulator,name=$DEVICE"
fi

echo "▶︎ План: $PLAN"
echo "▶︎ Destination: $DESTINATION"

rm -rf "$RESULT_BUNDLE"

xcodebuild test \
  -project LiftLog.xcodeproj \
  -scheme LiftLog \
  -testPlan "$PLAN" \
  -destination "$DESTINATION" \
  -resultBundlePath "$RESULT_BUNDLE" \
  -quiet \
  CODE_SIGNING_ALLOWED=NO
