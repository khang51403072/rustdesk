# RustDesk Dev Environment — Claude Code Setup Guide

Dùng file này để hướng dẫn Claude Code trên máy mới thiết lập môi trường build.

---

## Cách dùng

### Bước 1 — Copy script lên máy mới

```bash
# Nếu chưa clone repo, tải script trực tiếp:
curl -O https://raw.githubusercontent.com/khang51403072/rustdesk/custom/setup_macos.sh
chmod +x setup_macos.sh
```

### Bước 2 — Để Claude Code kiểm tra trước

Paste prompt này vào Claude Code trên máy mới:

---

**Prompt cho Claude Code:**

```
Chạy lệnh sau để kiểm tra môi trường hiện tại:

  bash setup_macos.sh --check

Đọc JSON output và xác định những gì cần cài theo trường `needs_install`.
Nếu `all_good` là `true` thì môi trường đã đầy đủ, không cần làm gì thêm.

Nếu có items trong `needs_install`, chạy:

  bash setup_macos.sh --install <component1> <component2> ...

Hoặc nếu cần cài toàn bộ từ đầu:

  bash setup_macos.sh

Sau khi cài xong, chạy lại `--check` để xác nhận `all_good: true`.
```

---

## Components có thể install riêng lẻ

| Tên trong `--install` | Mô tả |
|---|---|
| `homebrew` | Homebrew package manager |
| `brew_packages` | cmake, nasm, yasm, openssl@3, llvm, pkg-config, openjdk@17 |
| `android_env` | Env vars ANDROID_HOME, JAVA_HOME, etc. vào ~/.zshrc |
| `android_ndk` | NDK 27.1.12297006 qua sdkmanager |
| `rust` | Rust + rustup + tất cả targets |
| `cargo_ndk` | cargo-ndk + flutter_rust_bridge_codegen |
| `flutter` | Flutter 3.24.5 vào ~/Public/flutter |
| `vcpkg` | vcpkg vào ~/Public/vcpkg |
| `repo` | Clone repo + submodules |
| `ndk_toolchain_env` | CC_* AR_* env vars cho cross-compile |
| `pub_get` | flutter pub get |

## Ví dụ: chỉ cài Rust và Flutter

```bash
bash setup_macos.sh --install rust flutter
```

## Sau khi setup xong

```bash
source ~/.zshrc

# Build iOS
cd ~/Public/Project/rustdesk/flutter
./ios_arm64.sh && flutter build ipa --release

# Build Android
./ndk_arm64.sh && flutter build apk --release

# Lần đầu build Android: build vcpkg deps
bash build_android_deps.sh arm64-v8a
```

## Yêu cầu cài trước

- **Xcode** (từ App Store) + accept license: `sudo xcodebuild -license accept`
- **Android Studio** tại `/Applications/Android Studio.app`
- NDK cài qua Android Studio SDK Manager hoặc để script tự cài qua sdkmanager
