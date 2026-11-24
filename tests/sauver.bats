#!/usr/bin/env bats
# Tests de la commande steami-sauver.
# Lancer : bats tests/sauver.bats

setup() {
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.org
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.org
  SRC="$BATS_TEST_DIRNAME/../.devcontainer/source"
  export PATH="$SRC:$PATH"
  TMP="$(mktemp -d)"
  ORIGIN="$TMP/origin.git"
  DEPOT="$TMP/depot"
  git init -q --bare -b main "$ORIGIN"
  mkdir -p "$DEPOT/src"
  echo '[env:steami]' > "$DEPOT/platformio.ini"
  echo 'void setup(){}' > "$DEPOT/src/main.cpp"
  git -C "$DEPOT" init -q -b main
  git -C "$DEPOT" add -A
  git -C "$DEPOT" commit -q -m init
  cd "$DEPOT"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

avec_origin() {
  git remote add origin "$ORIGIN"
  git push -q -u origin main
}

@test "sauver_commit_et_push" {
  avec_origin
  echo '// modif' >> src/main.cpp
  run steami-sauver
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$ORIGIN" log -1 --format=%s main)" = sauvegarde ]
}

@test "sauver_message" {
  avec_origin
  echo '// modif' >> src/main.cpp
  run steami-sauver "LED rouge"
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s)" = "LED rouge" ]
}

@test "sauver_rien_de_neuf" {
  avec_origin
  run steami-sauver
  [ "$status" -eq 0 ]
  [[ "$output" == *"rien de nouveau à enregistrer"* ]]
  [[ "$output" == *"→ git push"* ]]
}

@test "sauver_branche_sans_amont" {
  avec_origin
  git switch -q -c essai
  echo '// modif' >> src/main.cpp
  run steami-sauver
  [ "$status" -eq 0 ]
  [[ "$output" == *"git push -u origin essai"* ]]
  git --git-dir="$ORIGIN" rev-parse --verify -q essai
}

@test "sauver_sans_origin" {
  echo '// modif' >> src/main.cpp
  run steami-sauver "local"
  [ "$status" -eq 1 ]
  [ "$(git log -1 --format=%s)" = local ]
  [[ "$output" == *"Publish Branch"* ]]
}

@test "sauver_push_refuse" {
  avec_origin
  mkdir -p "$ORIGIN/hooks"
  printf '#!/bin/sh\necho "Permission denied" >&2\nexit 1\n' > "$ORIGIN/hooks/pre-receive"
  chmod +x "$ORIGIN/hooks/pre-receive"
  echo '// modif' >> src/main.cpp
  run steami-sauver "refus"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Use this template"* ]]
  [[ "$output" == *"enregistré dans le Codespace"* ]]
  [[ "$output" == *"fetch first"* ]]
  [[ "$output" == *"git pull"* ]]
  [ "$(git log -1 --format=%s)" = refus ]
}

@test "sauver_head_detachee" {
  avec_origin
  git checkout -q --detach
  run steami-sauver
  [ "$status" -eq 1 ]
  [[ "$output" == *"git switch main"* ]]
}

@test "sauver_push_sans_identifiants" {
  avec_origin
  # Faux git : imite l'échec d'authentification d'une session SSH pour push.
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/git" <<'EOT'
#!/bin/sh
if [ "$1" = push ]; then
  echo "fatal: could not read Username for 'https://github.com': No such device or address" >&2
  exit 128
fi
exec /usr/bin/git "$@"
EOT
  chmod +x "$TMP/bin/git"
  export PATH="$TMP/bin:$PATH"
  echo '// modif' >> src/main.cpp
  run steami-sauver "ssh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not read Username"* ]]
  [[ "$output" == *"GitHub n'a pas pu vous identifier"* ]]
  [[ "$output" == *"terminal de VS Code"* ]]
  [[ "$output" != *"Use this template"* ]]
  [[ "$output" != *"✗ ✗"* ]]
  [ "$(git log -1 --format=%s)" = ssh ]
}

@test "sauver_push_auth_authentication_failed" {
  avec_origin
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/git" <<'EOT'
#!/bin/sh
if [ "$1" = push ]; then
  printf '%b\n' "remote: Invalid credentials\nfatal: Authentication failed for 'https://github.com/x/y.git/'" >&2
  exit 128
fi
exec /usr/bin/git "$@"
EOT
  chmod +x "$TMP/bin/git"
  export PATH="$TMP/bin:$PATH"
  echo '// modif' >> src/main.cpp
  run steami-sauver "auth"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Authentication failed"* ]]
  [[ "$output" == *"GitHub n'a pas pu vous identifier"* ]]
  [[ "$output" != *"Use this template"* ]]
  [[ "$output" != *"✗ ✗"* ]]
}

@test "sauver_push_auth_terminal_prompts_disabled" {
  avec_origin
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/git" <<'EOT'
#!/bin/sh
if [ "$1" = push ]; then
  printf '%b\n' "fatal: could not read Password: terminal prompts disabled" >&2
  exit 128
fi
exec /usr/bin/git "$@"
EOT
  chmod +x "$TMP/bin/git"
  export PATH="$TMP/bin:$PATH"
  echo '// modif' >> src/main.cpp
  run steami-sauver "auth"
  [ "$status" -eq 1 ]
  [[ "$output" == *"terminal prompts disabled"* ]]
  [[ "$output" == *"GitHub n'a pas pu vous identifier"* ]]
  [[ "$output" != *"Use this template"* ]]
  [[ "$output" != *"✗ ✗"* ]]
}

@test "sauver_push_auth_invalid_username_or_token" {
  avec_origin
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/git" <<'EOT'
#!/bin/sh
if [ "$1" = push ]; then
  printf '%b\n' "remote: Invalid username or token. Password authentication is not supported for Git operations." >&2
  exit 128
fi
exec /usr/bin/git "$@"
EOT
  chmod +x "$TMP/bin/git"
  export PATH="$TMP/bin:$PATH"
  echo '// modif' >> src/main.cpp
  run steami-sauver "auth"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid username or token"* ]]
  [[ "$output" == *"GitHub n'a pas pu vous identifier"* ]]
  [[ "$output" != *"Use this template"* ]]
  [[ "$output" != *"✗ ✗"* ]]
}
