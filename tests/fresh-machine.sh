#!/usr/bin/env bash
# End-to-end test: run install.sh in a clean Ubuntu container and assert the
# new-machine path works (and is idempotent). Requires Docker; skips without it.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not available" >&2
  exit 0
fi

docker run --rm -v "$REPO:/repo:ro" ubuntu:24.04 bash -euo pipefail -c '
  apt-get update -qq
  apt-get install -y -qq sudo git curl ca-certificates >/dev/null
  useradd -m -s /bin/bash tester
  echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
  cp -r /repo /home/tester/my-zsh
  chown -R tester:tester /home/tester/my-zsh
  sudo -u tester -H bash /home/tester/my-zsh/tests/_in_container.sh
'
echo "fresh-machine test passed."
