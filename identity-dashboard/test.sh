#!/bin/bash
# ================================================================
# test.sh — Smoke tests for gidas-identity
# ================================================================
# Run locally (or on pve-ad) to verify the build and CLI syntax.
# ================================================================

set -e

PASS=0
FAIL=0

green() { echo -e "\033[32m✓ $1\033[0m"; }
red()   { echo -e "\033[31m✗ $1\033[0m"; }

# ── 1. Docker build ────────────────────────────────────────────
echo "=== Smoke Tests ==="
echo ""

echo "1. Building Docker image..."
if docker build -t gidas-identity:test . > /dev/null 2>&1; then
    green "Docker build succeeded"
    PASS=$((PASS + 1))
else
    red "Docker build failed"
    FAIL=$((FAIL + 1))
fi

# ── 2. Main --help ─────────────────────────────────────────────
echo "2. Testing main --help..."
if docker run --rm gidas-identity:test --help 2>&1 | grep -q "gidas-identity"; then
    green "Main --help works"
    PASS=$((PASS + 1))
else
    red "Main --help failed"
    FAIL=$((FAIL + 1))
fi

# ── 3. User --help ─────────────────────────────────────────────
echo "3. Testing user --help..."
if docker run --rm gidas-identity:test user --help 2>&1 | grep -q "Manage user"; then
    green "User --help works"
    PASS=$((PASS + 1))
else
    red "User --help failed"
    FAIL=$((FAIL + 1))
fi

# ── 4. Group --help ────────────────────────────────────────────
echo "4. Testing group --help..."
if docker run --rm gidas-identity:test group --help 2>&1 | grep -q "Manage group"; then
    green "Group --help works"
    PASS=$((PASS + 1))
else
    red "Group --help failed"
    FAIL=$((FAIL + 1))
fi

# ── 5. HBAC --help ─────────────────────────────────────────────
echo "5. Testing hbac --help..."
if docker run --rm gidas-identity:test hbac --help 2>&1 | grep -q "Manage.*HBAC"; then
    green "HBAC --help works"
    PASS=$((PASS + 1))
else
    red "HBAC --help failed"
    FAIL=$((FAIL + 1))
fi

# ── 6. User password --help ────────────────────────────────────
echo "6. Testing user password --help..."
if docker run --rm gidas-identity:test user password --help 2>&1 | grep -q "Reset or set"; then
    green "User password --help works"
    PASS=$((PASS + 1))
else
    red "User password --help failed"
    FAIL=$((FAIL + 1))
fi

# ── 7. Python syntax check ─────────────────────────────────────
echo "7. Verifying Python syntax..."
if python3 -c "
import ast, pathlib, sys
errors = []
for f in sorted(pathlib.Path('app').rglob('*.py')):
    try:
        ast.parse(f.read_text())
    except SyntaxError as e:
        errors.append(f'{f}: {e}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
else:
    print('  All files OK')
"; then
    green "Python syntax check passed"
    PASS=$((PASS + 1))
else
    red "Python syntax check failed"
    FAIL=$((FAIL + 1))
fi

# ── Summary ────────────────────────────────────────────────────
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
exit ${FAIL}
