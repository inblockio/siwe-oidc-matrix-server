#!/usr/bin/env bash
# =============================================================================
# adapters/siwx-oidc-realstack.sh — encapsulate the siwx-oidc real-stack e2e
# tests against the LOCAL hermetic stack (siwx-e2eh-*).
#
# Runs an integration TEST TARGET (the `--test <NAME>` file), passing through
# `--ignored` (these tests are #[ignore]'d so they only run on demand against a
# live stack). Optionally restricts to specific test fns appended after the
# target name. Streams stdout/stderr to the artifact file; returns cargo's RC.
#
# Usage:
#   adapters/siwx-oidc-realstack.sh <artifact_file> <test_target> [<test_fn> ...]
#     e.g. siwx-oidc-realstack.sh art.txt e2e_msc3861 full_lifecycle
#          siwx-oidc-realstack.sh art.txt e2e_msc3861            # whole target
#
# Env overrides:
#   SIWX_OIDC_DIR  siwx-oidc checkout. Default: <parent of this repo>/siwx-oidc
#                  (repo-relative, NOT a hardcoded $HOME path). OIDC_E2EH_DIR is
#                  still honoured as the legacy override name.
#   SIWEOIDC_HOST  default http://localhost:18081
#   MATRIX_HOST    default http://localhost:18080
#
# Exit codes: 2 = could not run (precondition); 3 = ran but judged nothing
# (filter matched no test); otherwise cargo's own code. See adapters/_common.sh.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_common.sh
. "$SCRIPT_DIR/_common.sh"

ARTIFACT="${1:?usage: siwx-oidc-realstack.sh <artifact_file> <test_target> [test_fn...]}"
shift
TARGET="${1:?need a test target (e.g. e2e_msc3861)}"
shift || true   # remaining args (if any) are specific test fns / filters

SIWEOIDC_HOST="${SIWEOIDC_HOST:-http://localhost:18081}"
MATRIX_HOST="${MATRIX_HOST:-http://localhost:18080}"

# Some live tests must observe or seed SYNAPSE-side state, which needs a
# short-TTL admin token, which needs the MAS shared secret. Example:
# `e2e_did_field_live`'s self-heal leg mints one to plant a value the way a
# pre-denylist write would have, then proves the next sign-in restores it.
#
# The secret is not in the adapter's environment, so fall back to the harness
# env file — the same file up.sh reads to inject it into the containers. Never
# echoed: it is passed straight into the test process. Tests that do not need it
# are unaffected, and tests that do skip CLEANLY when it is absent rather than
# quietly degrading into a status-code-only check.
ENV_FILE="${ENV_FILE:-$(cd "$SCRIPT_DIR/../.." && pwd)/.env.e2e}"
if [ -z "${MAS_SHARED_SECRET:-}" ] && [ -f "$ENV_FILE" ]; then
  MAS_SHARED_SECRET="$(sed -n 's/^MAS_SHARED_SECRET=//p' "$ENV_FILE" | head -1)"
fi

# Sets $SIWX_OIDC_DIR_RESOLVED, or exits 2 having written the reason to $ARTIFACT.
resolve_siwx_oidc_dir "$ARTIFACT" "$TARGET"
OIDC_DIR="$SIWX_OIDC_DIR_RESOLVED"

command -v cargo >/dev/null 2>&1 || adapter_die "$ARTIFACT" 2 \
  "ADAPTER PRECONDITION FAILED: cargo not on PATH."

# Refuse to run against an unexpected / unreproducible checkout. Recording the
# revision was never enough — the harness would otherwise test whatever branch
# this sibling checkout happened to be sitting on.
assert_checkout_revision "$ARTIFACT" "$OIDC_DIR" "siwx-oidc checkout" \
  "${E2E_EXPECT_SHA:-}" "${E2E_EXPECT_REF:-}"

{
  echo "===== siwx-oidc real-stack adapter ====="
  echo "checkout     : $OIDC_DIR"
  echo "revision     : $(describe_checkout "$OIDC_DIR")"
  echo "test target  : $TARGET"
  echo "test filters : ${*:-<whole target>}"
  echo "siweoidc host: $SIWEOIDC_HOST"
  echo "matrix host  : $MATRIX_HOST"
  echo "========================================"
} >>"$ARTIFACT"

CARGO_OUT="$(mktemp -t siwx-adapter-out.XXXXXX)"
trap 'rm -f "$CARGO_OUT"' EXIT

set +e
( cd "$OIDC_DIR" && \
  SIWEOIDC_HOST="$SIWEOIDC_HOST" \
  MATRIX_HOST="$MATRIX_HOST" \
  MAS_SHARED_SECRET="${MAS_SHARED_SECRET:-}" \
  cargo test --test "$TARGET" -- --ignored --test-threads=1 --nocapture "$@" \
) >"$CARGO_OUT" 2>&1
RC=$?
set -e 2>/dev/null || true

cat "$CARGO_OUT" >>"$ARTIFACT"
assert_tests_actually_ran "$ARTIFACT" "$CARGO_OUT" "$RC"; RC=$?
report_skip_markers      "$ARTIFACT" "$CARGO_OUT" "$RC"; RC=$?
exit "$RC"
