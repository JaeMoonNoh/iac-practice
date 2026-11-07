#!/usr/bin/env bash
# =====================================================================
# bootstrap.sh — 새 컴퓨터에서 이 리포를 바로 쓸 수 있게 준비
#   1) mise 설치 (없으면)
#   2) mise.toml 에 고정된 버전의 terraform / tflint / aws-cli 설치
#   3) Docker 동작 여부 확인 (Docker는 자동 설치하지 않음 → README 참고)
# 여러 번 실행해도 안전합니다 (idempotent).
# =====================================================================
set -euo pipefail

cd "$(dirname "$0")/.."

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }

# ---- 1. mise ---------------------------------------------------------
if ! command -v mise >/dev/null 2>&1; then
  info "mise 가 없어 설치합니다."
  if command -v brew >/dev/null 2>&1; then
    brew install mise
  else
    # macOS(brew 없음) / Linux / WSL 공통 공식 설치 스크립트
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi
ok "mise $(mise --version | awk '{print $1}')"

# ---- 2. 고정 버전 도구 설치 --------------------------------------------
info "mise.toml 에 정의된 도구를 설치합니다 (처음엔 몇 분 걸릴 수 있음)."
mise trust --yes mise.toml >/dev/null
mise install
ok "$(mise exec -- terraform version | head -1)"
ok "$(mise exec -- tflint --version | head -1)"
ok "$(mise exec -- aws --version)"

# ---- 3. Docker -------------------------------------------------------
command -v docker >/dev/null 2>&1 \
  || fail "docker 가 없습니다. README의 'Docker 설치' 절을 참고해 수동 설치하세요."
docker info >/dev/null 2>&1 \
  || fail "docker 데몬이 꺼져 있습니다. Docker Desktop / OrbStack / Colima 를 실행하세요."
docker compose version >/dev/null 2>&1 \
  || fail "docker compose v2 가 필요합니다."
ok "docker $(docker version --format '{{.Server.Version}}') / compose $(docker compose version --short)"

cat <<'MSG'

준비 완료! 다음 순서로 진행하세요.
   make up      # Floci 기동
   make init    # terraform init
   make plan    # 연결 확인
   make apply   # data 조회 결과 출력 (리소스 생성 없음)

(선택) 셸에서 cd 할 때 mise 환경변수가 자동 적용되게 하려면:
   echo 'eval "$(mise activate zsh)"' >> ~/.zshrc   # bash면 zsh → bash
MSG
