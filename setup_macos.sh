#!/usr/bin/env bash
# RustDesk macOS dev environment setup
# Prerequisites: Xcode and Android Studio already installed
#
# Usage:
#   ./setup_macos.sh           — install everything missing
#   ./setup_macos.sh --check   — audit only, output JSON report (no changes)
#   ./setup_macos.sh --install homebrew rust flutter vcpkg ...
#                              — install only listed components

set -euo pipefail

# ─── Colors (disabled when piped / --check) ───────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ─── Config ───────────────────────────────────────────────────────────────────
FLUTTER_VERSION="3.24.5"
FLUTTER_DIR="$HOME/Public/flutter"
VCPKG_DIR="$HOME/Public/vcpkg"
NDK_VERSION="27.1.12297006"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
FLUTTER_RUST_BRIDGE_VERSION="1.80.1"
CARGO_NDK_VERSION="4.1.2"
REPO_REMOTE="https://github.com/khang51403072/rustdesk.git"
REPO_DIR="$HOME/Public/Project/rustdesk"

RUST_TARGETS=(
    aarch64-apple-darwin
    x86_64-apple-darwin
    aarch64-apple-ios
    x86_64-apple-ios
    aarch64-linux-android
    armv7-linux-androideabi
    i686-linux-android
    x86_64-linux-android
)

BREW_PACKAGES=(cmake nasm yasm openssl@3 llvm pkg-config openjdk@17)

# ─── Parse args ───────────────────────────────────────────────────────────────
MODE="install-all"   # install-all | check | install-some
INSTALL_LIST=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)   MODE="check"; shift ;;
        --install) MODE="install-some"; shift; INSTALL_LIST=("$@"); break ;;
        *)         error "Unknown argument: $1" ;;
    esac
done

# ─── Check helpers (pure reads, no side effects) ──────────────────────────────

chk_xcode()   { xcode-select -p &>/dev/null && echo "ok" || echo "missing"; }
chk_android_studio() { [[ -d "/Applications/Android Studio.app" ]] && echo "ok" || echo "missing"; }
chk_homebrew() { command -v brew &>/dev/null && echo "ok" || echo "missing"; }

chk_brew_pkg() {
    local pkg="$1"
    brew list "$pkg" &>/dev/null && echo "ok" || echo "missing"
}

chk_rust() {
    command -v rustc &>/dev/null || { echo "missing"; return; }
    local ver; ver=$(rustc --version | awk '{print $2}')
    # compare semver simply
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    local req_major req_minor
    req_major=$(echo "1.75" | cut -d. -f1)
    req_minor=$(echo "1.75" | cut -d. -f2)
    if [[ "$major" -gt "$req_major" ]] || \
       [[ "$major" -eq "$req_major" && "$minor" -ge "$req_minor" ]]; then
        echo "$ver"
    else
        echo "outdated:$ver"
    fi
}

chk_rust_target() {
    rustup target list --installed 2>/dev/null | grep -qx "$1" && echo "ok" || echo "missing"
}

chk_cargo_ndk() {
    command -v cargo-ndk &>/dev/null && cargo ndk --version 2>/dev/null | head -1 || echo "missing"
}

chk_flutter_rust_bridge() {
    command -v flutter_rust_bridge_codegen &>/dev/null \
        && flutter_rust_bridge_codegen --version 2>/dev/null | head -1 \
        || echo "missing"
}

chk_flutter() {
    local flutter_bin="$FLUTTER_DIR/bin/flutter"
    [[ -f "$flutter_bin" ]] || { echo "missing"; return; }
    local ver; ver=$("$flutter_bin" --version 2>/dev/null | awk 'NR==1{print $2}')
    echo "${ver:-unknown}"
}

chk_ndk() {
    [[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ]] && echo "ok" || echo "missing"
}

chk_vcpkg() {
    [[ -f "$VCPKG_DIR/vcpkg" ]] && echo "ok" || echo "missing"
}

chk_repo() {
    [[ -d "$REPO_DIR/.git" ]] && echo "ok" || echo "missing"
}

chk_shell_env() {
    local var="$1"
    # check if var is exported in current env OR defined in shell rc
    local rc_file="$HOME/.zshrc"
    [[ "$SHELL" == *"bash"* ]] && rc_file="$HOME/.bashrc"
    grep -qF "$var" "$rc_file" 2>/dev/null && echo "ok" || echo "missing"
}

# ─── --check mode: audit and output JSON ──────────────────────────────────────
run_check() {
    # Collect all statuses
    local xcode android_studio homebrew rust ndk flutter vcpkg repo

    xcode=$(chk_xcode)
    android_studio=$(chk_android_studio)
    homebrew=$(chk_homebrew)
    rust=$(chk_rust)
    ndk=$(chk_ndk)
    flutter=$(chk_flutter)
    vcpkg=$(chk_vcpkg)
    repo=$(chk_repo)

    # brew packages
    local brew_json=""
    for pkg in "${BREW_PACKAGES[@]}"; do
        local st; st=$(chk_brew_pkg "$pkg")
        brew_json+="\"$pkg\": \"$st\","
    done
    brew_json="${brew_json%,}"  # trim trailing comma

    # rust targets
    local targets_json=""
    for t in "${RUST_TARGETS[@]}"; do
        local st
        if [[ "$rust" == "missing" ]]; then st="missing"
        else st=$(chk_rust_target "$t"); fi
        targets_json+="\"$t\": \"$st\","
    done
    targets_json="${targets_json%,}"

    local cargo_ndk; cargo_ndk=$(chk_cargo_ndk)
    local frb; frb=$(chk_flutter_rust_bridge)

    # env vars to check
    local env_json=""
    for var in ANDROID_HOME ANDROID_NDK_HOME VCPKG_ROOT JAVA_HOME NDK_TOOLCHAIN; do
        local st; st=$(chk_shell_env "$var")
        env_json+="\"$var\": \"$st\","
    done
    env_json="${env_json%,}"

    # Determine what needs action
    local needs_action=()
    [[ "$xcode"          == "missing"    ]] && needs_action+=("xcode_cli")
    [[ "$android_studio" == "missing"    ]] && needs_action+=("android_studio")
    [[ "$homebrew"       == "missing"    ]] && needs_action+=("homebrew")
    [[ "$rust"           == "missing" || "$rust" == outdated* ]] && needs_action+=("rust")
    [[ "$ndk"            == "missing"    ]] && needs_action+=("android_ndk")
    [[ "$flutter"        == "missing"    ]] && needs_action+=("flutter")
    [[ "$vcpkg"          == "missing"    ]] && needs_action+=("vcpkg")
    [[ "$repo"           == "missing"    ]] && needs_action+=("repo")
    [[ "$cargo_ndk"      == "missing"    ]] && needs_action+=("cargo_ndk")
    [[ "$frb"            == "missing"    ]] && needs_action+=("flutter_rust_bridge")

    for pkg in "${BREW_PACKAGES[@]}"; do
        [[ "$(chk_brew_pkg "$pkg")" == "missing" ]] && needs_action+=("brew:$pkg")
    done

    if [[ "$rust" != "missing" ]]; then
        for t in "${RUST_TARGETS[@]}"; do
            [[ "$(chk_rust_target "$t")" == "missing" ]] && needs_action+=("rust_target:$t")
        done
    fi

    # Build needs_action JSON array
    local na_json=""
    for item in "${needs_action[@]}"; do
        na_json+="\"$item\","
    done
    na_json="${na_json%,}"

    # Output JSON
    cat <<EOF
{
  "rustdesk_setup_check": true,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "machine": "$(uname -n)",
  "arch": "$(uname -m)",
  "required_versions": {
    "rust_min": "1.75",
    "flutter": "$FLUTTER_VERSION",
    "ndk": "$NDK_VERSION",
    "cargo_ndk": "$CARGO_NDK_VERSION",
    "flutter_rust_bridge": "$FLUTTER_RUST_BRIDGE_VERSION"
  },
  "status": {
    "xcode_cli": "$xcode",
    "android_studio": "$android_studio",
    "homebrew": "$homebrew",
    "rust": "$rust",
    "cargo_ndk": "$cargo_ndk",
    "flutter_rust_bridge": "$frb",
    "flutter": "$flutter",
    "android_ndk_$NDK_VERSION": "$ndk",
    "vcpkg": "$vcpkg",
    "repo": "$repo",
    "brew_packages": { $brew_json },
    "rust_targets": { $targets_json },
    "shell_env_vars": { $env_json }
  },
  "needs_install": [$na_json],
  "all_good": $([ ${#needs_action[@]} -eq 0 ] && echo "true" || echo "false")
}
EOF
}

# ─── Install helpers ──────────────────────────────────────────────────────────
append_to_shell() {
    local line="$1"
    local rc_file="$HOME/.zshrc"
    [[ "$SHELL" == *"bash"* ]] && rc_file="$HOME/.bashrc"
    if ! grep -qF "$line" "$rc_file" 2>/dev/null; then
        echo "$line" >> "$rc_file"
        info "Added to $rc_file: $line"
    fi
}

# ─── Install functions ────────────────────────────────────────────────────────
install_homebrew() {
    step "Homebrew"
    command -v brew &>/dev/null && { success "Already installed: $(brew --version | head -1)"; return; }
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        append_to_shell 'eval "$(/opt/homebrew/bin/brew shellenv)"'
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    success "Homebrew installed"
}

install_brew_packages() {
    step "Brew packages"
    for pkg in "${BREW_PACKAGES[@]}"; do
        if brew list "$pkg" &>/dev/null; then
            info "$pkg — already installed"
        else
            info "Installing $pkg..."
            brew install "$pkg"
        fi
    done
    # openjdk@17 system symlink
    if [[ ! -f "/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home/bin/java" ]]; then
        sudo ln -sfn "$(brew --prefix openjdk@17)/libexec/openjdk.jdk" \
            /Library/Java/JavaVirtualMachines/openjdk-17.jdk 2>/dev/null || true
    fi
    success "Brew packages ready"
}

setup_android_env() {
    step "Android / Java environment variables"
    local java_home="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
    local ndk_path="$ANDROID_HOME/ndk/$NDK_VERSION"
    local vars=(
        "export JAVA_HOME=\"$java_home\""
        'export PATH="$JAVA_HOME/bin:$PATH"'
        "export ANDROID_HOME=\"$ANDROID_HOME\""
        'export PATH="$PATH:$ANDROID_HOME/platform-tools"'
        'export PATH="$PATH:$ANDROID_HOME/tools"'
        'export PATH="$PATH:$ANDROID_HOME/tools/bin"'
        'export PATH="$PATH:$ANDROID_HOME/emulator"'
        'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"'
        "export ANDROID_NDK_HOME=\"$ndk_path\""
        'export NDK_HOME="$ANDROID_NDK_HOME"'
        'export PATH="$PATH:$ANDROID_NDK_HOME"'
    )
    for v in "${vars[@]}"; do append_to_shell "$v"; done
    export JAVA_HOME="$java_home"
    export PATH="$JAVA_HOME/bin:$PATH"
    export ANDROID_NDK_HOME="$ndk_path"
    export NDK_HOME="$ANDROID_NDK_HOME"
    export PATH="$PATH:$ANDROID_NDK_HOME"
    success "Android env vars configured"
}

install_android_ndk() {
    step "Android NDK $NDK_VERSION"
    [[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ]] && { success "Already installed"; return; }
    local sdkmgr=""
    command -v sdkmanager &>/dev/null && sdkmgr="sdkmanager"
    [[ -z "$sdkmgr" && -f "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]] \
        && sdkmgr="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"
    if [[ -z "$sdkmgr" ]]; then
        warn "sdkmanager not in PATH — install NDK $NDK_VERSION manually:"
        warn "  Android Studio → SDK Manager → SDK Tools → NDK (Side by side) → $NDK_VERSION"
        return
    fi
    yes | "$sdkmgr" "ndk;$NDK_VERSION"
    success "NDK $NDK_VERSION installed"
}

install_rust() {
    step "Rust toolchain"
    if command -v rustup &>/dev/null; then
        info "rustup present, running update..."
        rustup update stable
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
        # shellcheck source=/dev/null
        source "$HOME/.cargo/env"
        append_to_shell 'source "$HOME/.cargo/env"'
    fi
    success "rustc $(rustc --version | awk '{print $2}')"

    step "Rust targets"
    for t in "${RUST_TARGETS[@]}"; do
        rustup target add "$t" && info "  $t"
    done
}

install_cargo_tools() {
    step "Cargo tools"
    if ! cargo ndk --version &>/dev/null; then
        info "Installing cargo-ndk v$CARGO_NDK_VERSION..."
        cargo install cargo-ndk --version "$CARGO_NDK_VERSION" --locked
    else
        info "cargo-ndk — already installed"
    fi
    if ! flutter_rust_bridge_codegen --version &>/dev/null; then
        info "Installing flutter_rust_bridge_codegen v$FLUTTER_RUST_BRIDGE_VERSION..."
        cargo install flutter_rust_bridge_codegen --version "$FLUTTER_RUST_BRIDGE_VERSION" --locked
    else
        info "flutter_rust_bridge_codegen — already installed"
    fi
    success "Cargo tools ready"
}

install_flutter() {
    step "Flutter $FLUTTER_VERSION"
    if [[ -f "$FLUTTER_DIR/bin/flutter" ]]; then
        local cur; cur=$("$FLUTTER_DIR/bin/flutter" --version 2>/dev/null | awk 'NR==1{print $2}')
        if [[ "$cur" == "$FLUTTER_VERSION" ]]; then
            success "Already installed ($cur)"
        else
            warn "Found Flutter $cur at $FLUTTER_DIR (expected $FLUTTER_VERSION)"
            warn "Remove $FLUTTER_DIR and rerun to get the exact version."
        fi
    else
        mkdir -p "$HOME/Public"
        local arch; arch=$(uname -m)
        local archive="flutter_macos_${FLUTTER_VERSION}-stable.tar.xz"
        [[ "$arch" == "arm64" ]] && archive="flutter_macos_arm64_${FLUTTER_VERSION}-stable.tar.xz"
        local url="https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/$archive"
        info "Downloading $archive..."
        curl -L "$url" -o "/tmp/$archive"
        tar xf "/tmp/$archive" -C "$HOME/Public"
        rm "/tmp/$archive"
    fi
    append_to_shell "export PATH=\"\$PATH:$FLUTTER_DIR/bin\""
    export PATH="$PATH:$FLUTTER_DIR/bin"
    flutter config --no-analytics 2>/dev/null || true
    flutter config --android-sdk "$ANDROID_HOME" 2>/dev/null || true
    yes | flutter doctor --android-licenses 2>/dev/null || true
    success "Flutter ready: $("$FLUTTER_DIR/bin/flutter" --version 2>/dev/null | head -1)"
}

install_vcpkg() {
    step "vcpkg"
    if [[ -f "$VCPKG_DIR/vcpkg" ]]; then
        success "Already installed at $VCPKG_DIR"
    else
        mkdir -p "$HOME/Public"
        git clone https://github.com/microsoft/vcpkg.git "$VCPKG_DIR"
        "$VCPKG_DIR/bootstrap-vcpkg.sh" -disableMetrics
    fi
    append_to_shell "export VCPKG_ROOT=\"$VCPKG_DIR\""
    append_to_shell 'export PATH="$PATH:$VCPKG_ROOT"'
    export VCPKG_ROOT="$VCPKG_DIR"
    export PATH="$PATH:$VCPKG_ROOT"
    success "vcpkg ready"
}

setup_repo() {
    step "RustDesk repository"
    if [[ -d "$REPO_DIR/.git" ]]; then
        info "Repo exists, updating submodules..."
        git -C "$REPO_DIR" submodule update --init --recursive
        success "Submodules up to date"
        return
    fi
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone --recurse-submodules "$REPO_REMOTE" "$REPO_DIR"
    success "Repo cloned to $REPO_DIR"
}

setup_ndk_toolchain_env() {
    step "NDK cross-compile toolchain env"
    local host_tag; host_tag=$(ls "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/" 2>/dev/null | head -1)
    if [[ -z "$host_tag" ]]; then
        warn "NDK not found at $ANDROID_NDK_HOME, skipping"
        return
    fi
    local toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host_tag/bin"
    local vars=(
        "export NDK_TOOLCHAIN=\"$toolchain\""
        'export PATH="$NDK_TOOLCHAIN:$PATH"'
        'export CC_aarch64_linux_android="$NDK_TOOLCHAIN/aarch64-linux-android21-clang"'
        'export CC_armv7_linux_androideabi="$NDK_TOOLCHAIN/armv7a-linux-androideabi21-clang"'
        'export CC_i686_linux_android="$NDK_TOOLCHAIN/i686-linux-android21-clang"'
        'export CC_x86_64_linux_android="$NDK_TOOLCHAIN/x86_64-linux-android21-clang"'
        'export AR_aarch64_linux_android="$NDK_TOOLCHAIN/llvm-ar"'
        'export AR_armv7_linux_androideabi="$NDK_TOOLCHAIN/llvm-ar"'
    )
    for v in "${vars[@]}"; do append_to_shell "$v"; done
    export NDK_TOOLCHAIN="$toolchain"
    export PATH="$NDK_TOOLCHAIN:$PATH"
    success "NDK toolchain env configured"
}

flutter_pub_get() {
    step "flutter pub get"
    [[ -d "$REPO_DIR/flutter" ]] || { warn "flutter/ dir not found, skipping"; return; }
    (cd "$REPO_DIR/flutter" && flutter pub get)
    success "Flutter packages fetched"
}

print_next_steps() {
    echo -e "\n${BOLD}${GREEN}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  Done! Next steps:${NC}"
    echo -e "${BOLD}${GREEN}══════════════════════════════════════════${NC}"
    cat <<'TIPS'

  Reload shell:
    source ~/.zshrc

  Build iOS (arm64):
    cd ~/Public/Project/rustdesk/flutter
    ./ios_arm64.sh            # compile Rust lib
    flutter build ipa --release

  Build Android (arm64):
    cd ~/Public/Project/rustdesk/flutter
    ./ndk_arm64.sh            # compile Rust lib
    flutter build apk --release

  Build vcpkg deps for Android (first time only):
    cd ~/Public/Project/rustdesk/flutter
    bash build_android_deps.sh arm64-v8a

TIPS
}

# ─── Component dispatch table ─────────────────────────────────────────────────
run_component() {
    case "$1" in
        homebrew)              install_homebrew ;;
        brew_packages|brew:*) install_brew_packages ;;
        android_env)           setup_android_env ;;
        android_ndk)           install_android_ndk ;;
        rust|rust_target:*)   install_rust ;;
        cargo_ndk|flutter_rust_bridge) install_cargo_tools ;;
        flutter)               install_flutter ;;
        vcpkg)                 install_vcpkg ;;
        repo)                  setup_repo ;;
        ndk_toolchain_env)     setup_ndk_toolchain_env ;;
        pub_get)               flutter_pub_get ;;
        *) warn "Unknown component: $1" ;;
    esac
}

# ─── Full install sequence ────────────────────────────────────────────────────
run_install_all() {
    echo -e "${BOLD}RustDesk macOS Setup${NC}"
    echo "========================================"

    # Prereq checks (hard stops)
    if ! xcode-select -p &>/dev/null; then
        info "Installing Xcode Command Line Tools..."
        xcode-select --install
        echo "Re-run this script after Xcode CLI tools finish installing."
        exit 0
    fi
    [[ -d "/Applications/Android Studio.app" ]] \
        || error "Android Studio not found — install it first."

    install_homebrew
    install_brew_packages
    setup_android_env
    install_android_ndk
    install_rust
    install_cargo_tools
    install_flutter
    install_vcpkg
    setup_repo
    setup_ndk_toolchain_env
    flutter_pub_get
    print_next_steps
}

# ─── Entry point ─────────────────────────────────────────────────────────────
case "$MODE" in
    check)
        run_check
        ;;
    install-some)
        if [[ ${#INSTALL_LIST[@]} -eq 0 ]]; then
            error "No components listed. Example: --install rust flutter vcpkg"
        fi
        for comp in "${INSTALL_LIST[@]}"; do
            run_component "$comp"
        done
        ;;
    install-all)
        run_install_all
        ;;
esac
