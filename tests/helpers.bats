#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO/lib/helpers.sh"
  TMP="$(mktemp -d)"
  SRC="$TMP/source-file"
  echo "new-content" > "$SRC"
}

teardown() {
  rm -rf "$TMP"
}

@test "have: true for an existing command" {
  run have sh
  [ "$status" -eq 0 ]
}

@test "have: false for a missing command" {
  run have definitely-not-a-real-command-xyz
  [ "$status" -ne 0 ]
}

@test "backup_and_link: creates symlink when dest is absent" {
  backup_and_link "$SRC" "$TMP/dest"
  [ -L "$TMP/dest" ]
  [ "$(readlink -f "$TMP/dest")" = "$(readlink -f "$SRC")" ]
}

@test "backup_and_link: backs up an existing file, then links" {
  echo "old-content" > "$TMP/dest"
  backup_and_link "$SRC" "$TMP/dest"
  [ -L "$TMP/dest" ]
  run cat "$TMP"/dest.backup.*
  [ "$status" -eq 0 ]
  [ "$output" = "old-content" ]
}

@test "backup_and_link: idempotent — no backup when already linked" {
  backup_and_link "$SRC" "$TMP/dest"
  backup_and_link "$SRC" "$TMP/dest"
  run bash -c "ls -1 $TMP/dest.backup.* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "backup_and_link: DRY_RUN makes no filesystem changes" {
  export DRY_RUN=1
  backup_and_link "$SRC" "$TMP/dest"
  [ ! -e "$TMP/dest" ]
}

@test "backup_and_link: backs up a symlink pointing elsewhere, then relinks" {
  local other="$TMP/other-file"
  echo "other" > "$other"
  ln -s "$other" "$TMP/dest"
  backup_and_link "$SRC" "$TMP/dest"
  [ -L "$TMP/dest" ]
  [ "$(readlink -f "$TMP/dest")" = "$(readlink -f "$SRC")" ]
  run ls -1 "$TMP"/dest.backup.*
  [ "$status" -eq 0 ]
}
