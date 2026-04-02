[group("test")]
[doc("Run all justfile e2e tests")]
test:
  #!/usr/bin/env bash
  set -uo pipefail
  PASS=0; FAIL=0
  run_test() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
      echo "  PASS  $name"; PASS=$((PASS + 1))
    else
      echo "  FAIL  $name"; FAIL=$((FAIL + 1))
    fi
  }

  echo "=== Justfile E2E Tests ==="
  echo ""

  # --- Recipe listing ---
  echo "[recipes]"
  run_test "just --list succeeds" just --list
  run_test "just --list shows init" bash -c 'just --list | grep -q "init"'
  run_test "just --list shows local-build" bash -c 'just --list | grep -q "local-build"'
  run_test "just --list shows remote-build" bash -c 'just --list | grep -q "remote-build"'
  run_test "just --list shows generate-app-labels" bash -c 'just --list | grep -q "generate-app-labels"'
  run_test "just --list shows test" bash -c 'just --list | grep -q "test"'

  # --- Module listing ---
  echo ""
  echo "[modules]"
  run_test "core module listed" bash -c 'just --list | grep -q "core"'
  run_test "build module listed" bash -c 'just --list | grep -q "build"'

  # --- Groups ---
  echo ""
  echo "[groups]"
  for group in core build ci; do
    run_test "group '$group' exists" bash -c "just --list | grep -q '\\[$group\\]'"
  done

  # --- local-build preconditions ---
  echo ""
  echo "[local-build preconditions]"
  run_test "local-build rejects nonexistent app" bash -c '! just local-build nonexistent-app-xyz 2>&1'

  # Verify all real apps have required files
  for dir in apps/*/; do
    app=$(basename "$dir")
    run_test "$app has Dockerfile" test -f "apps/$app/Dockerfile"
    run_test "$app has docker-bake.hcl" test -f "apps/$app/docker-bake.hcl"
    run_test "$app has tests.yaml" test -f "apps/$app/tests.yaml"
  done

  # --- remote-build preconditions ---
  echo ""
  echo "[remote-build preconditions]"
  run_test "gh cli available" command -v gh
  if gh auth status >/dev/null 2>&1; then
    echo "  PASS  gh auth active"; PASS=$((PASS + 1))
  else
    echo "  SKIP  gh auth active (run 'gh auth login' to enable remote-build)"
  fi

  # --- generate-app-labels ---
  echo ""
  echo "[generate-app-labels]"
  # Run against a temp copy to avoid mutating the real labels file
  TMPDIR=$(mktemp -d)
  trap 'rm -rf "$TMPDIR"' EXIT
  cp .github/labels.yaml "$TMPDIR/labels-backup.yaml"
  # Create empty array to test from scratch
  echo '[]' > .github/labels.yaml
  just generate-app-labels
  APP_COUNT=$(ls -d apps/*/ | wc -l | tr -d ' ')
  LABEL_COUNT=$(yq 'length' .github/labels.yaml)
  run_test "generated $APP_COUNT app labels" bash -c "[[ $LABEL_COUNT -eq $APP_COUNT ]]"
  run_test "labels have correct color" bash -c 'yq -e "all_c(.color == \"0e8a16\")" .github/labels.yaml'
  run_test "labels have app/ prefix" bash -c 'yq -e "all_c(.name | test(\"^app/\"))" .github/labels.yaml'
  # Restore original
  cp "$TMPDIR/labels-backup.yaml" .github/labels.yaml

  # --- Summary ---
  echo ""
  TOTAL=$((PASS + FAIL))
  echo "=== $PASS/$TOTAL passed ==="
  [[ $FAIL -eq 0 ]] || exit 1
