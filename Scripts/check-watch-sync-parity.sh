#!/usr/bin/env bash
#
# Формат обмена с часами (WorkoutSyncModels.swift) продублирован в двух целях —
# у них нет общего фреймворка. Скрипт падает, если копии разошлись.
# Дёшево, поэтому годится и для pre-commit хука, и для CI перед сборкой.

set -euo pipefail

cd "$(dirname "$0")/.."

PHONE="LiftLog/WorkoutSyncModels.swift"
WATCH="LiftLogWatchApp Watch App/WorkoutSyncModels.swift"

if diff -u "$PHONE" "$WATCH"; then
  echo "✓ WorkoutSyncModels.swift идентичны в обеих целях"
else
  echo >&2
  echo "✗ Копии WorkoutSyncModels.swift разошлись — приведите их к одному виду вручную" >&2
  exit 1
fi
