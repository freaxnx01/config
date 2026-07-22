#!/usr/bin/env bash
# setup/bootstrap.sh — DEPRECATED. Claude provisioning moved to agent-workflow.
#
# Kept so the old one-line bootstrap URL, and any notes or muscle memory that
# still use it, keep working. It forwards every argument to the new entry point
# and prints the URL you should use from now on (ADR-007 in agent-workflow).
#
# New URL:
#   curl -fsSL https://raw.githubusercontent.com/freaxnx01/agent-workflow/main/setup/bootstrap.sh | bash

set -euo pipefail

NEW_URL="https://raw.githubusercontent.com/freaxnx01/agent-workflow/main/setup/bootstrap.sh"

echo "⚠ DEPRECATED: Claude provisioning now lives in freaxnx01/agent-workflow." >&2
echo "  Update your bookmark to:" >&2
echo "    curl -fsSL $NEW_URL | bash" >&2
echo "  Forwarding there now…" >&2
echo >&2

curl -fsSL "$NEW_URL" | bash -s -- "$@"
