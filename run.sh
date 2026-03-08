#!/bin/bash

set -euo pipefail

# CyberStrikeAI 원클릭 배포 시작 스크립트
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 색상 초기화

# 색상 메시지 출력 함수
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; }
note() { echo -e "${CYAN}ℹ️  $1${NC}"; }

# 임시 미러 설정 (이 스크립트 실행 중에만 적용)
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

# 원래 환경 변수 저장 (복원용)
ORIGINAL_PIP_INDEX_URL="${PIP_INDEX_URL:-}"
ORIGINAL_GOPROXY="${GOPROXY:-}"

# 진행 상태 표시 함수
show_progress() {
    local pid=$1
    local message=$2
    local i=0
    local dots=""

    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi

    while kill -0 "$pid" 2>/dev/null; do
        i=$((i + 1))
        case $((i % 4)) in
            0) dots="." ;;
            1) dots=".." ;;
            2) dots="..." ;;
            3) dots="...." ;;
        esac
        printf "\r${BLUE}⏳ %s%s${NC}" "$message" "$dots"
        sleep 0.5

        if ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
    done
    printf "\r"
}

echo ""
echo "=========================================="
echo "  CyberStrikeAI 원클릭 배포 시작 스크립트"
echo "=========================================="
echo ""

echo ""
warning "⚠️  주의: 이 스크립트는 임시 미러를 사용하여 다운로드를 가속합니다"
echo ""
info "Python pip 임시 미러:"
echo "  ${PIP_INDEX_URL}"
info "Go Proxy 임시 미러:"
echo "  ${GOPROXY}"
echo ""
note "이 설정은 스크립트 실행 중에만 적용되며 시스템 설정을 변경하지 않습니다"
echo ""
sleep 1

CONFIG_FILE="$ROOT_DIR/config.yaml"
VENV_DIR="$ROOT_DIR/venv"
REQUIREMENTS_FILE="$ROOT_DIR/requirements.txt"
BINARY_NAME="cyberstrike-ai"

# 설정 파일 확인
if [ ! -f "$CONFIG_FILE" ]; then
    error "설정 파일 config.yaml 이 존재하지 않습니다"
    info "프로젝트 루트 디렉토리에서 스크립트를 실행했는지 확인하세요"
    exit 1
fi

# Python 환경 확인
check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        error "python3 를 찾을 수 없습니다"
        echo ""
        info "Python 3.10 이상을 먼저 설치해주세요:"
        echo "  macOS:   brew install python3"
        echo "  Ubuntu:  sudo apt-get install python3 python3-venv"
        echo "  CentOS:  sudo yum install python3 python3-pip"
        exit 1
    fi

    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
    PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

    if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 10 ]); then
        error "Python 버전이 너무 낮습니다: $PYTHON_VERSION (3.10 이상 필요)"
        exit 1
    fi

    success "Python 환경 확인 완료: $PYTHON_VERSION"
}

# Go 환경 확인
check_go() {
    if ! command -v go >/dev/null 2>&1; then
        error "Go 를 찾을 수 없습니다"
        echo ""
        info "Go 1.21 이상을 먼저 설치해주세요:"
        echo "  macOS:   brew install go"
        echo "  Ubuntu:  sudo apt-get install golang-go"
        echo "  CentOS:  sudo yum install golang"
        echo "  또는:    https://go.dev/dl/"
        exit 1
    fi

    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    GO_MAJOR=$(echo "$GO_VERSION" | cut -d. -f1)
    GO_MINOR=$(echo "$GO_VERSION" | cut -d. -f2)

    if [ "$GO_MAJOR" -lt 1 ] || ([ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -lt 21 ]); then
        error "Go 버전이 너무 낮습니다: $GO_VERSION (1.21 이상 필요)"
        exit 1
    fi

    success "Go 환경 확인 완료: $(go version)"
}

# Python 가상환경 설정
setup_python_env() {
    if [ ! -d "$VENV_DIR" ]; then
        info "Python 가상환경 생성 중..."
        python3 -m venv "$VENV_DIR"
        success "가상환경 생성 완료"
    else
        info "Python 가상환경이 이미 존재합니다"
    fi

    info "가상환경 활성화 중..."
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"

    if [ -f "$REQUIREMENTS_FILE" ]; then
        echo ""
        note "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        note "⚠️  임시 pip 미러 사용 중 (이번 스크립트 실행에만 적용)"
        note "   미러 주소: ${PIP_INDEX_URL}"
        note "   영구 설정이 필요하면 환경변수 PIP_INDEX_URL 을 설정하세요"
        note "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        info "pip 업그레이드 중..."
        pip install --index-url "$PIP_INDEX_URL" --upgrade pip >/dev/null 2>&1 || true

        info "Python 패키지 설치 중..."
        echo ""

        PIP_LOG=$(mktemp)
        (
            set +e
            pip install --index-url "$PIP_INDEX_URL" -r "$REQUIREMENTS_FILE" >"$PIP_LOG" 2>&1
            echo $? > "${PIP_LOG}.exit"
        ) &
        PIP_PID=$!

        sleep 0.1

        if kill -0 "$PIP_PID" 2>/dev/null; then
            show_progress "$PIP_PID" "패키지 설치 중"
        else
            sleep 0.2
        fi

        wait "$PIP_PID" 2>/dev/null || true

        PIP_EXIT_CODE=0
        if [ -f "${PIP_LOG}.exit" ]; then
            PIP_EXIT_CODE=$(cat "${PIP_LOG}.exit" 2>/dev/null || echo "1")
            rm -f "${PIP_LOG}.exit" 2>/dev/null || true
        else
            if [ -f "$PIP_LOG" ] && grep -q -i "error\|failed\|exception" "$PIP_LOG" 2>/dev/null; then
                PIP_EXIT_CODE=1
            fi
        fi

        if [ $PIP_EXIT_CODE -eq 0 ]; then
            success "Python 패키지 설치 완료"
        else
            if grep -q "angr" "$PIP_LOG" && grep -q "Rust compiler\|can't find Rust" "$PIP_LOG"; then
                warning "angr 설치 실패 (Rust 컴파일러 필요)"
                echo ""
                info "angr 는 선택적 의존성으로 주로 바이너리 분석 도구에 사용됩니다"
                info "angr 가 필요하다면 먼저 Rust 를 설치하세요:"
                echo "  macOS/Ubuntu: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
                echo "  또는:         https://rustup.rs/"
                echo ""
                info "다른 패키지는 설치되었으며 계속 실행할 수 있습니다 (일부 도구 사용 불가)"
            else
                warning "일부 Python 패키지 설치에 실패했지만 계속 시도합니다"
                warning "문제가 발생하면 오류 메시지를 확인하고 누락된 패키지를 수동으로 설치하세요"
                echo ""
                info "오류 상세 (마지막 10줄):"
                tail -n 10 "$PIP_LOG" | sed 's/^/  /'
                echo ""
            fi
        fi
        rm -f "$PIP_LOG"
    else
        warning "requirements.txt 를 찾을 수 없습니다. Python 패키지 설치를 건너뜁니다"
    fi
}

# Go 프로젝트 빌드
build_go_project() {
    echo ""
    note "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    note "⚠️  임시 Go Proxy 사용 중 (이번 스크립트 실행에만 적용)"
    note "   Proxy 주소: ${GOPROXY}"
    note "   영구 설정이 필요하면 환경변수 GOPROXY 를 설정하세요"
    note "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    info "Go 의존성 다운로드 중..."
    GO_DOWNLOAD_LOG=$(mktemp)
    (
        set +e
        export GOPROXY="$GOPROXY"
        go mod download >"$GO_DOWNLOAD_LOG" 2>&1
        echo $? > "${GO_DOWNLOAD_LOG}.exit"
    ) &
    GO_DOWNLOAD_PID=$!

    sleep 0.1

    if kill -0 "$GO_DOWNLOAD_PID" 2>/dev/null; then
        show_progress "$GO_DOWNLOAD_PID" "Go 의존성 다운로드 중"
    else
        sleep 0.2
    fi

    wait "$GO_DOWNLOAD_PID" 2>/dev/null || true

    GO_DOWNLOAD_EXIT_CODE=0
    if [ -f "${GO_DOWNLOAD_LOG}.exit" ]; then
        GO_DOWNLOAD_EXIT_CODE=$(cat "${GO_DOWNLOAD_LOG}.exit" 2>/dev/null || echo "1")
        rm -f "${GO_DOWNLOAD_LOG}.exit" 2>/dev/null || true
    else
        if [ -f "$GO_DOWNLOAD_LOG" ] && grep -q -i "error\|failed" "$GO_DOWNLOAD_LOG" 2>/dev/null; then
            GO_DOWNLOAD_EXIT_CODE=1
        fi
    fi
    rm -f "$GO_DOWNLOAD_LOG" 2>/dev/null || true

    if [ $GO_DOWNLOAD_EXIT_CODE -ne 0 ]; then
        error "Go 의존성 다운로드 실패"
        exit 1
    fi
    success "Go 의존성 다운로드 완료"

    info "프로젝트 빌드 중..."
    GO_BUILD_LOG=$(mktemp)
    (
        set +e
        export GOPROXY="$GOPROXY"
        go build -o "$BINARY_NAME" cmd/server/main.go >"$GO_BUILD_LOG" 2>&1
        echo $? > "${GO_BUILD_LOG}.exit"
    ) &
    GO_BUILD_PID=$!

    sleep 0.1

    if kill -0 "$GO_BUILD_PID" 2>/dev/null; then
        show_progress "$GO_BUILD_PID" "프로젝트 빌드 중"
    else
        sleep 0.2
    fi

    wait "$GO_BUILD_PID" 2>/dev/null || true

    GO_BUILD_EXIT_CODE=0
    if [ -f "${GO_BUILD_LOG}.exit" ]; then
        GO_BUILD_EXIT_CODE=$(cat "${GO_BUILD_LOG}.exit" 2>/dev/null || echo "1")
        rm -f "${GO_BUILD_LOG}.exit" 2>/dev/null || true
    else
        if [ -f "$GO_BUILD_LOG" ] && grep -q -i "error\|failed" "$GO_BUILD_LOG" 2>/dev/null; then
            GO_BUILD_EXIT_CODE=1
        fi
    fi

    if [ $GO_BUILD_EXIT_CODE -eq 0 ]; then
        success "프로젝트 빌드 완료: $BINARY_NAME"
        rm -f "$GO_BUILD_LOG"
    else
        error "프로젝트 빌드 실패"
        echo ""
        info "빌드 오류 상세:"
        cat "$GO_BUILD_LOG" | sed 's/^/  /'
        echo ""
        rm -f "$GO_BUILD_LOG"
        exit 1
    fi
}

# 재빌드 필요 여부 확인
need_rebuild() {
    if [ ! -f "$BINARY_NAME" ]; then
        return 0  # 빌드 필요
    fi

    if [ "$BINARY_NAME" -ot cmd/server/main.go ] || \
       [ "$BINARY_NAME" -ot go.mod ] || \
       find internal cmd -name "*.go" -newer "$BINARY_NAME" 2>/dev/null | grep -q .; then
        return 0  # 재빌드 필요
    fi

    return 1  # 빌드 불필요
}

# 메인 프로세스
main() {
    info "실행 환경 확인 중..."
    check_python
    check_go
    echo ""

    info "Python 환경 설정 중..."
    setup_python_env
    echo ""

    if need_rebuild; then
        info "프로젝트 빌드 준비 중..."
        build_go_project
    else
        success "실행 파일이 최신 상태입니다. 빌드를 건너뜁니다"
    fi
    echo ""

    success "모든 준비가 완료되었습니다!"
    echo ""
    info "CyberStrikeAI 서버 시작 중..."
    echo "=========================================="
    echo ""

    exec "./$BINARY_NAME"
}

# 메인 프로세스 실행
main
