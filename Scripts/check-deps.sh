#!/bin/bash
# Fitness functions (ARCHITECTURE.md §18): dependency and RT-purity checks.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

# 1. Render imports only CoreAudio / CAtomic / Darwin — no UI, no Foundation.
bad=$(grep -rn -E "^import " Sources/MixBarCore/Render/ \
      | grep -v -E "import (CoreAudio|CAtomic|Darwin)$" || true)
if [ -n "$bad" ]; then
    echo "FAIL: Render has forbidden imports:"; echo "$bad"; fail=1
fi

# 2. No UI frameworks anywhere in MixBarCore (AppKit is allowed in Discovery only).
bad=$(grep -rn -E "import (SwiftUI|Combine)" Sources/MixBarCore/ || true)
if [ -n "$bad" ]; then
    echo "FAIL: MixBarCore imports UI frameworks:"; echo "$bad"; fail=1
fi
bad=$(grep -rn -E "import AppKit" Sources/MixBarCore/ \
      | grep -v "Sources/MixBarCore/Discovery/" || true)
if [ -n "$bad" ]; then
    echo "FAIL: AppKit allowed only in Discovery:"; echo "$bad"; fail=1
fi

# 3. RT purity: no blocking primitives in Render.
bad=$(grep -rn -E "Timer|DispatchQueue|Logger|\.perform\(|NSLock" Sources/MixBarCore/Render/ || true)
if [ -n "$bad" ]; then
    echo "FAIL: forbidden symbols in Render (RT purity):"; echo "$bad"; fail=1
fi

# 4. No network anywhere: nothing to check yet (no entitlements in repo);
#    enforced at signing time via codesign -d --entitlements.

if [ "$fail" -eq 0 ]; then
    echo "OK: all dependency and RT-purity checks passed"
fi
exit "$fail"
