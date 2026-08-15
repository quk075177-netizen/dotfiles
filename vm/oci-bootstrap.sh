#!/usr/bin/env bash
set -uo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

FAIL_LOG="$HOME/bootstrap-failures.log"
: > "$FAIL_LOG"

step() {
  local name="$1"
  shift

  echo
  echo "=== [$name] 시작 ==="

  if ! "$@"; then
    echo "!!! [$name] 실패 - 계속 진행" | tee -a "$FAIL_LOG"
    return 0
  fi

  echo "=== [$name] 완료 ==="
}


# ============================================================
# uv + Python
# ============================================================

install_uv_python() {
  curl -LsSf https://astral.sh/uv/install.sh | sh

  export PATH="$HOME/.local/bin:$PATH"

  # aider 제약이 사라졌으므로 특정 Python minor를
  # 억지로 고정할 필요 없음.
  uv python install 3.13
}


# ============================================================
# Node.js (fnm)
# ============================================================

install_node() {
  curl -fsSL https://fnm.vercel.app/install |
    bash -s -- --skip-shell

  export PATH="$HOME/.local/share/fnm:$PATH"

  eval "$(fnm env)"

  fnm install --lts
  fnm default lts-latest
}


# ============================================================
# zoxide
# ============================================================

install_zoxide() {
  curl -sS \
    https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh |
    bash
}


# ============================================================
# Ubuntu fd / bat command aliases
# ============================================================

link_fd_bat() {
  mkdir -p "$HOME/.local/bin"

  if command -v fdfind >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" \
      "$HOME/.local/bin/fd"
  fi

  if command -v batcat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" \
      "$HOME/.local/bin/bat"
  fi
}


# ============================================================
# Git
# ============================================================

configure_git() {
  git config --global init.defaultBranch main

  if command -v delta >/dev/null 2>&1; then
    git config --global core.pager delta
    git config --global interactive.diffFilter \
      "delta --color-only"
    git config --global delta.navigate true
  fi
}


# ============================================================
# fish
# ============================================================

configure_fish() {
  mkdir -p "$HOME/.config/fish"

  cat > "$HOME/.config/fish/config.fish" <<'FISHEOF'
# ~/.local/bin
fish_add_path $HOME/.local/bin

# fnm
fish_add_path $HOME/.local/share/fnm

if type -q fnm
    fnm env --use-on-cd --shell fish | source
end

# zoxide
if type -q zoxide
    zoxide init fish | source
end
FISHEOF
}


# ============================================================
# code-server
# ============================================================

install_code_server() {
  curl -fsSL https://code-server.dev/install.sh | sh

  mkdir -p "$HOME/.config/code-server"

  local pw
  pw="$(openssl rand -base64 18)"

  cat > "$HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${pw}
cert: false
EOF

  chmod 600 "$HOME/.config/code-server/config.yaml"

  # linger가 이미 cloud-init에서 활성화되어 있음.
  # 아직 user bus가 올라오지 않은 경우 machinectl 사용.
  if command -v machinectl >/dev/null 2>&1; then
    sudo machinectl shell "$USER@" \
      /bin/bash -lc \
      "XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user enable --now code-server"
  else
    systemctl --user enable --now code-server
  fi

  echo
  echo "code-server password:"
  echo "$pw"
}


# ============================================================
# code-server extensions
# ============================================================

install_extensions() {
  local extensions=(
    dbaeumer.vscode-eslint
    esbenp.prettier-vscode
    charliermarsh.ruff
    ms-python.python
    ms-pyright.pyright
    editorconfig.editorconfig
    eamodio.gitlens
    usernamehw.errorlens
    yzhang.markdown-all-in-one
    pkief.material-icon-theme
  )

  local failed=()

  for ext in "${extensions[@]}"; do
    if ! code-server \
      --install-extension "$ext" \
      --force
    then
      failed+=("$ext")
    fi
  done

  if [ "${#failed[@]}" -gt 0 ]; then
    echo "확장 설치 실패: ${failed[*]}" >&2
    return 1
  fi
}


# ============================================================
# VS Code settings
# ============================================================

configure_vscode_settings() {
  local settings_dir
  settings_dir="$HOME/.local/share/code-server/User"

  mkdir -p "$settings_dir"

  cat > "$settings_dir/settings.json" <<'EOF'
{
  "editor.formatOnSave": true,
  "editor.defaultFormatter": "esbenp.prettier-vscode",
  "editor.rulers": [100],
  "editor.tabSize": 2,
  "editor.bracketPairColorization.enabled": true,
  "editor.guides.bracketPairs": true,

  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "files.trimFinalNewlines": true,

  "python.languageServer": "None",
  "python.analysis.typeCheckingMode": "basic",

  "eslint.validate": [
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact"
  ],

  "[python]": {
    "editor.defaultFormatter": "charliermarsh.ruff",
    "editor.tabSize": 4,
    "editor.codeActionsOnSave": {
      "source.organizeImports.ruff": "explicit",
      "source.fixAll.ruff": "explicit"
    }
  },

  "[typescript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": "explicit"
    }
  },

  "[typescriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": "explicit"
    }
  },

  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": "explicit"
    }
  },

  "[javascriptreact]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.codeActionsOnSave": {
      "source.fixAll.eslint": "explicit"
    }
  },

  "[json]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },

  "[jsonc]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },

  "[markdown]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode"
  },

  "workbench.iconTheme": "material-icon-theme",
  "gitlens.hovers.currentLine.over": "line"
}
EOF
}


# ============================================================
# Run
# ============================================================

step "uv+python" \
  install_uv_python

step "node(fnm)" \
  install_node

step "zoxide" \
  install_zoxide

step "fd/bat link" \
  link_fd_bat

step "git config" \
  configure_git

step "fish config" \
  configure_fish

step "code-server" \
  install_code_server

step "extensions" \
  install_extensions

step "vscode settings" \
  configure_vscode_settings


# ============================================================
# Result
# ============================================================

echo

if [ -s "$FAIL_LOG" ]; then
  echo "=========================================="
  echo "일부 bootstrap 단계 실패"
  echo "=========================================="
  cat "$FAIL_LOG"
  echo
  echo "로그:"
  echo "$FAIL_LOG"
else
  echo "=========================================="
  echo "Bootstrap 완료"
  echo "=========================================="
fi

echo
echo "Architecture : $(uname -m)"
echo "CPU          : $(nproc)"
echo

command -v eza   >/dev/null && echo "eza   : $(eza --version | head -1)"
command -v delta >/dev/null && echo "delta : $(delta --version)"
command -v rg    >/dev/null && echo "rg    : $(rg --version | head -1)"
command -v fd    >/dev/null && echo "fd    : $(fd --version)"
command -v bat   >/dev/null && echo "bat   : $(bat --version)"
command -v node  >/dev/null && echo "node  : $(node --version)"
command -v uv    >/dev/null && echo "uv    : $(uv --version)"
