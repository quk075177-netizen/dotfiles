#!/usr/bin/env bash
# ============================================================
# 사용자 컨텍스트 개발환경 부트스트랩 스크립트
#
# 실행 주체: sudo -iu <user> bash bootstrap-user.sh
#   (root가 아닌 대상 유저의 $HOME 기준으로 모든 파일이 생성/소유됨)
#
# 사용법:
#   1) 이 파일을 GitHub 등 별도 저장소에 올린다 (cloud-init 파일과 분리)
#   2) cloud-init에서는 curl로 받아서 실행만 한다:
#        sudo -iu ubuntu bash -c \
#          "curl -fsSL https://raw.githubusercontent.com/<you>/<repo>/main/bootstrap-user.sh | bash"
#   3) 스크립트 수정 시 이 파일만 고치면 되고, cloud-init user-data는
#      건드릴 필요 없음 (재부팅/재생성 없이 다음 VM부터 바로 반영)
# ============================================================
set -euxo pipefail

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
FAIL_LOG="$HOME/bootstrap-failures.log"
: > "$FAIL_LOG"

# 개별 단계 실패해도 스크립트 전체가 죽지 않도록 감싸는 헬퍼.
# (원본은 set -e라 한 단계 실패 = 이후 전부 스킵이었음.
#  code-server 하나 실패했다고 aider까지 안 깔리는 상황 방지)
step() {
  local name="$1"; shift
  echo "=== [$name] 시작 ==="
  if ! "$@"; then
    echo "!!! [$name] 실패 - 계속 진행" | tee -a "$FAIL_LOG"
    return 1
  fi
  echo "=== [$name] 완료 ==="
}

# ---- code-server 설치 ----
install_code_server() {
  curl -fsSL https://code-server.dev/install.sh | sh

  mkdir -p "$HOME/.config/code-server"
  local pw
  pw=$(openssl rand -base64 18)
  cat > "$HOME/.config/code-server/config.yaml" <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${pw}
cert: false
EOF
  chmod 600 "$HOME/.config/code-server/config.yaml"

  # systemctl --user는 cloud-init 직후 D-Bus user session이
  # 아직 안 붙어 있어 "Failed to connect to bus"로 실패하는 경우가 흔함.
  # loginctl enable-linger(런타임 쪽 runcmd에서 선행)를 걸어도
  # 세션 준비 타이밍이 보장되지 않으므로 machinectl로 우회.
  if command -v machinectl >/dev/null 2>&1; then
    sudo machinectl shell "$USER@" /bin/bash -c \
      "XDG_RUNTIME_DIR=/run/user/$(id -u) systemctl --user enable --now code-server"
  else
    systemctl --user enable --now code-server
  fi
}

# ---- uv + python ----
install_uv_python() {
  curl -LsSf https://astral.sh/uv/install.sh | sh
  source "$HOME/.local/bin/env"

  # 3.12/3.13은 numpy==1.24.3 등 aider-chat 구버전 의존성이
  # 소스 빌드 자체를 실패시킴 (pkgutil.ImpImporter 제거로 setuptools 구버전 깨짐).
  # 3.11로 고정.
  uv python install 3.11
  uv python pin 3.11
}

# ---- Node.js (fnm) ----
install_node() {
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
  export PATH="$HOME/.local/share/fnm:$PATH"
  eval "$(fnm env)"
  fnm install --lts
  fnm default lts-latest
}

# ---- eza / delta: GitHub Releases 직접 설치 ----
# 버전 문자열을 하드코딩해 GitHub API rate limit(비인증 60회/시간, 같은 리전
# NAT 대역에서 여러 VM 동시 부팅 시 쉽게 소진됨)에 흔들리지 않게 함.
# 최신 버전 쓰고 싶으면 아래 EZA_VER/DELTA_VER만 갱신.
install_eza_delta() {
  mkdir -p "$HOME/.local/bin"
  local EZA_VER="v0.20.2"
  local DELTA_VER="v0.18.2"

  curl -Lo /tmp/eza.tar.gz \
    "https://github.com/eza-community/eza/releases/download/${EZA_VER}/eza_x86_64-unknown-linux-gnu.tar.gz"
  tar -xzf /tmp/eza.tar.gz -C "$HOME/.local/bin"

  curl -Lo /tmp/delta.deb \
    "https://github.com/dandavison/delta/releases/download/${DELTA_VER}/git-delta_${DELTA_VER#v}_amd64.deb"
  sudo dpkg -i /tmp/delta.deb || sudo apt-get install -f -y
}

# ---- zoxide ----
install_zoxide() {
  curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
}

# ---- fd / bat 심볼릭 링크 (Ubuntu 패키지명이 fdfind/batcat) ----
link_fd_bat() {
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
}

# ---- Aider ----
install_aider() {
  source "$HOME/.local/bin/env"
  uv tool install aider-chat --python 3.11
}

# ---- git 기본 설정 ----
configure_git() {
  git config --global init.defaultBranch main
  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
}

# ---- fish 설정 (PATH 보강) ----
configure_fish() {
  mkdir -p "$HOME/.config/fish"
  cat >> "$HOME/.config/fish/config.fish" <<'FISHEOF'
set -gx PATH $HOME/.local/bin $PATH
set -gx PATH $HOME/.local/share/fnm $PATH
fnm env --use-on-cd | source
zoxide init fish | source
FISHEOF
}

# ---- Hermes Agent ----
# TODO: 정확한 설치 방법(pip 패키지명 / git 저장소 URL) 확정되면 채우기
# install_hermes() {
#   git clone https://github.com/<org>/hermes-agent.git "$HOME/hermes-agent"
#   cd "$HOME/hermes-agent" && uv sync
# }

# ---- Tailscale Serve: 포트번호 없이 https://<hostname>.ts.net 으로 접속 가능하게 ----
# code-server(0.0.0.0:8080, cert: false)는 그대로 두고, Tailscale이 앞단에서
# TLS 종단 + 443 매핑을 대신 처리. tailscale up은 cloud-init runcmd에서
# 이 스크립트보다 먼저 실행되므로 이 시점엔 이미 연결돼 있어야 정상.
setup_tailscale_serve() {
  sudo tailscale serve --bg 8080
}

# ---- VS Code 확장: 린팅/포매팅 + 범용 ----
# code-server는 MS 마켓플레이스가 아니라 Open VSX를 쓰므로, Pylance처럼
# MS 프로프라이어터리 확장은 설치 불가. 개별 실패해도(마켓에 없거나
# 네트워크 이슈) 전체가 죽지 않도록 하나씩 || true로 감쌈.
install_extensions() {
  local extensions=(
    dbaeumer.vscode-eslint       # TS/JS 린팅
    esbenp.prettier-vscode       # TS/JS 포매팅
    charliermarsh.ruff           # Python 린팅+포매팅 (black/flake8/isort 대체)
    ms-python.python             # Python 언어 지원
    editorconfig.editorconfig    # 프로젝트별 들여쓰기/개행 규칙 자동 적용
    eamodio.gitlens              # git blame/히스토리 인라인 표시
    usernamehw.errorlens         # 에러/경고 줄 끝에 바로 표시
    yzhang.markdown-all-in-one   # 마크다운 미리보기/단축키
    pkief.material-icon-theme    # 파일 아이콘 테마
  )
  local failed=()
  for ext in "${extensions[@]}"; do
    if ! code-server --install-extension "$ext" --force; then
      failed+=("$ext")
    fi
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    echo "확장 설치 실패: ${failed[*]}" >&2
    return 1
  fi
}


step "uv+python"    install_uv_python
step "node(fnm)"    install_node
step "eza/delta"    install_eza_delta
step "zoxide"       install_zoxide
step "fd/bat link"  link_fd_bat
step "aider"        install_aider
step "git config"   configure_git
step "fish config"  configure_fish
step "code-server"  install_code_server
step "extensions"   install_extensions
step "tailscale serve" setup_tailscale_serve
# step "hermes"     install_hermes

if [ -s "$FAIL_LOG" ]; then
  echo "=== 아래 단계 실패, $HOME/bootstrap-failures.log 확인 ===" >&2
  cat "$FAIL_LOG" >&2
fi
