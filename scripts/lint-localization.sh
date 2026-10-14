#!/usr/bin/env bash
# lint-localization.sh: every String(localized:defaultValue:) key used in the Swift sources exists
# in App/OffMyPlate/Localizable.xcstrings (T28). Thin wrapper over check-localization.py.
# Fix a failure with: python3 scripts/check-localization.py --fix  (then review the new values).
set -euo pipefail
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/check-localization.py" "$@"
