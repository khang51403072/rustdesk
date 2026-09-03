#!/usr/bin/env bash
#
# run_customize.sh — trình chạy RustDesk / Desk Remote X có menu + theo dõi tiến trình
#
#   ./run_customize.sh                    # mở menu: quick action / chọn platform, device, schema
#   ./run_customize.sh --last             # chạy lại đúng cấu hình lần trước
#   ./run_customize.sh -p android -m release -d emulator-5554
#
set -o pipefail

FLUTTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$FLUTTER_DIR/.." && pwd)"
PKG="com.carriez.flutter_hbb"
HIST="$FLUTTER_DIR/.run_customize_history"
HIST_MAX=8

# ------------------------------------------------------------------ mặc định
PLATFORM=""      # android | ios | macos | web
MODE=""          # debug | profile | release  (schema)
DEVICE=""
DEVICE_NAME=""
ABI=""
RUNNER=""        # fast (adb install) | flutter (flutter run, hot reload)
AVD=""
SKIP_RUST=0
SKIP_BUILD=0
DO_CLEAN=0
DO_TAIL=0
INTERACTIVE=1
USE_LAST=0

usage() {
	cat <<'EOF'
run_customize.sh — chạy RustDesk / Desk Remote X

  ./run_customize.sh                 Mở menu (quick action từ các phiên trước + wizard)
  ./run_customize.sh --last          Chạy lại cấu hình gần nhất, không hỏi

Options (có bất kỳ cái nào -> bỏ qua menu):
  -p, --platform <android|ios|macos|web>
  -m, --mode <debug|profile|release>      "schema" build
  -d, --device <id>                       id từ `flutter devices`
      --abi <arm64-v8a|armeabi-v7a|x86_64|x86>   (android, mặc định dò theo device)
      --runner <fast|flutter>             fast = adb install + mở app; flutter = flutter run (hot reload)
      --avd <name>                        boot AVD này nếu chưa có device
      --skip-rust                         bỏ qua build lib Rust
      --skip-build                        bỏ qua build app
      --clean                             flutter clean trước
      --tail                              bám logcat sau khi mở (android + runner fast)
  -h, --help
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	-p | --platform) PLATFORM="$2"; INTERACTIVE=0; shift ;;
	-m | --mode) MODE="$2"; INTERACTIVE=0; shift ;;
	-d | --device) DEVICE="$2"; INTERACTIVE=0; shift ;;
	--abi) ABI="$2"; INTERACTIVE=0; shift ;;
	--runner) RUNNER="$2"; INTERACTIVE=0; shift ;;
	--avd) AVD="$2" ;;
	--release) MODE=release; INTERACTIVE=0 ;;
	--debug) MODE=debug; INTERACTIVE=0 ;;
	--profile) MODE=profile; INTERACTIVE=0 ;;
	--skip-rust) SKIP_RUST=1 ;;
	--skip-build) SKIP_BUILD=1 ;;
	--clean) DO_CLEAN=1 ;;
	--tail) DO_TAIL=1 ;;
	--last) USE_LAST=1; INTERACTIVE=0 ;;
	-h | --help) usage; exit 0 ;;
	*) echo "Tham số lạ: $1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

# ---------------------------------------------------------------------- màu mè
if [ -t 1 ] && [ -z "$NO_COLOR" ]; then
	C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_B=$'\033[1m'
	C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_YLW=$'\033[33m'; C_CYN=$'\033[36m'; C_MAG=$'\033[35m'
	TTY=1
else
	C_RST=; C_DIM=; C_B=; C_GRN=; C_RED=; C_YLW=; C_CYN=; C_MAG=; TTY=0
fi
OK_MARK=$'\xe2\x9c\x93'
BAD_MARK=$'\xe2\x9c\x97'
[ -t 0 ] || INTERACTIVE=0

cleanup() { tput cnorm 2>/dev/null; [ -n "$STATE" ] && rm -f "$STATE"; }
trap cleanup EXIT INT

LOG_DIR="$FLUTTER_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/run_customize-$(date +%Y%m%d-%H%M%S).log"
: >"$LOG"

hms() {
	local s=$1
	if [ "$s" -ge 60 ]; then printf '%dm%02ds' $((s / 60)) $((s % 60)); else printf '%ds' "$s"; fi
}
ago() { # epoch -> "3 phút trước"
	local d=$(( $(date +%s) - $1 ))
	if [ $d -lt 60 ]; then echo "vừa xong"
	elif [ $d -lt 3600 ]; then echo "$((d / 60)) phút trước"
	elif [ $d -lt 86400 ]; then echo "$((d / 3600)) giờ trước"
	else echo "$((d / 86400)) ngày trước"; fi
}
cols() { local c; c=$(tput cols 2>/dev/null) || c=100; [ -n "$c" ] && [ "$c" -gt 20 ] || c=100; echo "$c"; }
die() {
	printf '%s%s %s%s\n' "$C_RED$C_B" "$BAD_MARK" "$*" "$C_RST" >&2
	printf '%s  log: %s%s\n' "$C_DIM" "$LOG" "$C_RST" >&2
	exit 1
}

ADB="$(command -v adb 2>/dev/null)"
[ -n "$ADB" ] || ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"
EMULATOR="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"

# =============================================================== step engine ==
TOTAL_STEPS=0
STEP_IDX=0
SUMMARY=()
START_ALL=$SECONDS
SPIN_ARR=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# step "<tiêu đề>" "<regex dòng log muốn hiện>" <command...>
step() {
	local title="$1" filter="$2"
	shift 2
	STEP_IDX=$((STEP_IDX + 1))
	local start=$SECONDS tag
	tag=$(printf '[%d/%d]' "$STEP_IDX" "$TOTAL_STEPS")
	printf '\n=== STEP %s %s ===\n' "$tag" "$title" >>"$LOG"

	"$@" >>"$LOG" 2>&1 &
	local pid=$! i=0 w
	w=$(cols)
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$TTY" = 1 ]; then
			local note=""
			[ -n "$filter" ] && note=$(tail -n 400 "$LOG" | grep -aE "$filter" | tail -n 1 | tr -d '\r' | cut -c1-$((w - 40)))
			printf '\r\033[2K%s %s%s%s %s %s(%s)%s %s%s%s' \
				"$C_CYN${SPIN_ARR[$((i % 10))]}$C_RST" "$C_DIM" "$tag" "$C_RST" "$title" \
				"$C_DIM" "$(hms $((SECONDS - start)))" "$C_RST" "$C_DIM" "$note" "$C_RST"
		fi
		i=$((i + 1))
		sleep 0.12
	done
	wait "$pid"
	local rc=$? dur=$((SECONDS - start))
	[ "$TTY" = 1 ] && printf '\r\033[2K'
	if [ $rc -eq 0 ]; then
		printf '%s%s%s %s%s%s %s %s(%s)%s\n' "$C_GRN" "$OK_MARK" "$C_RST" "$C_DIM" "$tag" "$C_RST" "$title" "$C_DIM" "$(hms $dur)" "$C_RST"
		SUMMARY+=("$C_GRN$OK_MARK$C_RST $title $C_DIM($(hms $dur))$C_RST")
	else
		printf '%s%s%s %s%s%s %s %s(%s, exit %d)%s\n' "$C_RED" "$BAD_MARK" "$C_RST" "$C_DIM" "$tag" "$C_RST" "$title" "$C_DIM" "$(hms $dur)" "$rc" "$C_RST"
		printf '\n%s--- 40 dòng cuối của log ---%s\n' "$C_DIM" "$C_RST" >&2
		tail -n 40 "$LOG" >&2
		die "Hỏng ở bước: $title"
	fi
}

# ================================================================= devices ====
# mỗi dòng: id \t name \t platform \t kind \t sdk
list_devices() {
	flutter devices --machine 2>/dev/null | python3 -c '
import json,sys
try: ds=json.load(sys.stdin)
except Exception: ds=[]
def plat(t):
    if t.startswith("android"): return "android"
    if t=="ios": return "ios"
    if t=="darwin": return "macos"
    if t.startswith("web"): return "web"
    return t
for d in ds:
    if not d.get("isSupported",True): continue
    p=plat(d.get("targetPlatform",""))
    kind="emulator" if d.get("emulator") else "device"
    print("\t".join([d.get("id",""),d.get("name",""),p,kind,d.get("sdk","")]))
'
	# AVD chưa boot
	if [ -x "$EMULATOR" ]; then
		local running
		running=$("$ADB" devices 2>/dev/null | awk 'NR>1 && $2=="device"{print $1}' | wc -l)
		"$EMULATOR" -list-avds 2>/dev/null | while read -r a; do
			[ -n "$a" ] || continue
			[ "$running" -gt 0 ] && continue
			printf 'avd:%s\t%s\tandroid\tavd\tchưa chạy\n' "$a" "$a"
		done
	fi
}

# ================================================================= history ====
hist_add() {
	local line
	line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$(date +%s)" "$PLATFORM" "$MODE" "$DEVICE" "$DEVICE_NAME" "$ABI" "$RUNNER")
	local tmp
	tmp=$(mktemp)
	printf '%s\n' "$line" >"$tmp"
	# bỏ trùng (cùng platform+mode+device+runner), giữ mới nhất lên đầu
	[ -f "$HIST" ] && awk -F'\t' -v p="$PLATFORM" -v m="$MODE" -v d="$DEVICE" -v r="$RUNNER" \
		'!($2==p && $3==m && $4==d && $7==r)' "$HIST" >>"$tmp"
	head -n "$HIST_MAX" "$tmp" >"$HIST"
	rm -f "$tmp"
}

# ==================================================================== menu ====
# menu_select "Tiêu đề" "nhãn1<TAB>ghi chú" "nhãn2<TAB>ghi chú" ...
# -> MENU_RESULT = index đã chọn (0-based)
MENU_RESULT=0
menu_select() {
	local title="$1"
	shift
	local opts=("$@")
	local n=${#opts[@]} cur=0 drawn=0
	local main note key rest i

	printf '\n%s%s%s  %s(↑/↓ chọn · Enter xác nhận · q thoát)%s\n' "$C_B" "$title" "$C_RST" "$C_DIM" "$C_RST"
	tput civis 2>/dev/null
	while :; do
		[ $drawn -eq 1 ] && printf '\033[%dA' "$n"
		for ((i = 0; i < n; i++)); do
			main="${opts[$i]%%$'\t'*}"
			note=""
			case "${opts[$i]}" in *$'\t'*) note="${opts[$i]#*$'\t'}" ;; esac
			if [ $i -eq $cur ]; then
				printf '\r\033[2K %s❯ %s%s' "$C_CYN$C_B" "$main" "$C_RST"
			else
				printf '\r\033[2K   %s' "$main"
			fi
			[ -n "$note" ] && printf '  %s%s%s' "$C_DIM" "$note" "$C_RST"
			printf '\n'
		done
		drawn=1

		key=""
		IFS= read -rsn1 key
		case "$key" in
		'') # Enter
			tput cnorm 2>/dev/null
			MENU_RESULT=$cur
			return 0
			;;
		$'\033')
			rest=""
			IFS= read -rsn2 -t 1 rest
			case "$rest" in
			'[A') cur=$(((cur - 1 + n) % n)) ;;
			'[B') cur=$(((cur + 1) % n)) ;;
			'') tput cnorm 2>/dev/null; exit 0 ;; # Esc
			esac
			;;
		k | K) cur=$(((cur - 1 + n) % n)) ;;
		j | J) cur=$(((cur + 1) % n)) ;;
		q | Q) tput cnorm 2>/dev/null; exit 0 ;;
		[1-9])
			[ "$key" -le "$n" ] && cur=$((key - 1))
			;;
		esac
	done
}

hist_label() { # ts platform mode device devname abi runner -> nhãn phẳng (không màu)
	local s="$2 · $3 · ${5:-$4}"
	[ -n "$6" ] && s="$s · $6"
	[ "$7" = flutter ] && s="$s · hot reload"
	printf '%s' "$s"
}

menu() {
	local opts=() keys=() n=0
	printf '%s┌─ Desk Remote X · runner%s\n' "$C_B$C_CYN" "$C_RST"
	if [ -s "$HIST" ]; then
		while IFS=$'\t' read -r ts p m d dn abi r; do
			[ -n "$p" ] || continue
			keys+=("$ts	$p	$m	$d	$dn	$abi	$r")
			opts+=("$(hist_label "$ts" "$p" "$m" "$d" "$dn" "$abi" "$r")	$(ago "$ts")")
			n=$((n + 1))
		done <"$HIST"
	fi
	opts+=("Cấu hình mới…	chọn platform / device / schema")
	opts+=("Thoát	")

	menu_select "Quick action" "${opts[@]}"
	local sel=$MENU_RESULT

	if [ "$sel" -lt "$n" ]; then
		IFS=$'\t' read -r _ PLATFORM MODE DEVICE DEVICE_NAME ABI RUNNER <<<"${keys[$sel]}"
		if ! list_devices | cut -f1 | grep -qx "$DEVICE"; then
			printf '\n%s! Device %s không còn kết nối — chọn lại.%s\n' "$C_YLW" "$DEVICE" "$C_RST"
			pick_device_menu
		fi
	elif [ "$sel" -eq "$n" ]; then
		wizard
	else
		exit 0
	fi
}

pick_platform_menu() {
	menu_select "Platform" \
		"android	build lib NDK + apk" \
		"ios	cần device thật, Xcode" \
		"macos	desktop" \
		"web	chrome"
	local plats=(android ios macos web)
	PLATFORM="${plats[$MENU_RESULT]}"
}

pick_device_menu() {
	local rows=() opts=() note
	while IFS=$'\t' read -r id name plat kind sdk; do
		[ "$plat" = "$PLATFORM" ] || continue
		rows+=("$id	$name	$kind")
		note="$id · $kind · $sdk"
		[ "$PLATFORM" = ios ] && [ "$kind" = emulator ] && note="$note · ⚠ simulator: Xcode chỉ link lib device"
		opts+=("$name	$note")
	done < <(list_devices)
	[ ${#rows[@]} -gt 0 ] || die "Không có device nào cho platform $PLATFORM"
	menu_select "Device ($PLATFORM)" "${opts[@]}"
	IFS=$'\t' read -r DEVICE DEVICE_NAME _ <<<"${rows[$MENU_RESULT]}"
	[ -n "$DEVICE" ] || die "Lựa chọn không hợp lệ"
}

pick_mode_menu() {
	menu_select "Schema (build mode)" \
		"debug	nhanh, hot reload / debug được" \
		"profile	đo hiệu năng" \
		"release	bản phát hành, tối ưu"
	local modes=(debug profile release)
	MODE="${modes[$MENU_RESULT]}"
}

pick_runner_menu() {
	if [ "$PLATFORM" != android ]; then RUNNER=flutter; return; fi
	menu_select "Cách chạy" \
		"fast	build apk + adb install + mở app (nhanh nhất)" \
		"flutter	flutter run — hot reload, bám console"
	local runners=(fast flutter)
	RUNNER="${runners[$MENU_RESULT]}"
}

wizard() {
	pick_platform_menu
	pick_device_menu
	pick_mode_menu
	pick_runner_menu
}

# ================================================================== helpers ===
rust_target_for_abi() {
	case "$1" in
	arm64-v8a) echo aarch64-linux-android ;;
	armeabi-v7a) echo armv7-linux-androideabi ;;
	x86_64) echo x86_64-linux-android ;;
	x86) echo i686-linux-android ;;
	esac
}
vcpkg_triplet_for_abi() {
	case "$1" in
	arm64-v8a) echo arm64-android ;;
	armeabi-v7a) echo arm-neon-android ;;
	x86_64) echo x64-android ;;
	x86) echo x86-android ;;
	esac
}
flutter_platform_for_abi() {
	case "$1" in
	arm64-v8a) echo android-arm64 ;;
	armeabi-v7a) echo android-arm ;;
	x86_64) echo android-x64 ;;
	x86) echo android-x86 ;;
	esac
}

# ==================================================================== steps ===
preflight() {
	local missing=0
	for c in flutter cargo rustc; do
		command -v "$c" >/dev/null || { echo "THIẾU: $c không có trong PATH"; missing=1; }
	done
	echo "flutter : $(flutter --version 2>/dev/null | head -1)"
	echo "rustc   : $(rustc --version 2>/dev/null)"
	case "$PLATFORM" in
	android)
		cargo ndk --version >/dev/null 2>&1 || { echo "THIẾU: cargo-ndk (cargo install cargo-ndk)"; missing=1; }
		[ -x "$ADB" ] || { echo "THIẾU: adb tại $ADB"; missing=1; }
		[ -n "$ANDROID_NDK_HOME" ] && [ -d "$ANDROID_NDK_HOME" ] || { echo "THIẾU: ANDROID_NDK_HOME"; missing=1; }
		[ -n "$VCPKG_ROOT" ] && [ -d "$VCPKG_ROOT" ] || { echo "THIẾU: VCPKG_ROOT"; missing=1; }
		echo "ndk     : $ANDROID_NDK_HOME"
		echo "vcpkg   : $VCPKG_ROOT"
		;;
	ios | macos)
		command -v xcodebuild >/dev/null || { echo "THIẾU: xcodebuild"; missing=1; }
		echo "xcode   : $(xcodebuild -version 2>/dev/null | head -1)"
		[ -n "$VCPKG_ROOT" ] && [ -d "$VCPKG_ROOT" ] || { echo "THIẾU: VCPKG_ROOT"; missing=1; }
		;;
	esac
	echo "target  : $PLATFORM / $MODE / $DEVICE_NAME ($DEVICE)"
	return $missing
}

resolve_device() {
	if [ "$PLATFORM" = android ]; then
		# boot AVD nếu cần
		case "$DEVICE" in
		avd:*)
			local name="${DEVICE#avd:}"
			echo "Boot AVD $name ..."
			"$EMULATOR" -avd "$name" -netdelay none -netspeed full >/dev/null 2>&1 &
			"$ADB" wait-for-device
			until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 2; done
			DEVICE=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
			;;
		esac
		[ -n "$DEVICE" ] || DEVICE=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1; exit}')
		[ -n "$DEVICE" ] || { echo "Không có device android nào"; return 1; }
		local abi
		abi=$("$ADB" -s "$DEVICE" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
		[ -n "$ABI" ] || ABI="$abi"
		[ -n "$DEVICE_NAME" ] || DEVICE_NAME=$("$ADB" -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
		echo "device: $DEVICE ($DEVICE_NAME)  abi máy: $abi  dùng: $ABI"
	else
		echo "device: $DEVICE ($DEVICE_NAME)"
	fi
	printf '%s\t%s\t%s\n' "$DEVICE" "$DEVICE_NAME" "$ABI" >"$STATE"
}

pub_get() { cd "$FLUTTER_DIR" && flutter pub get; }
do_clean() { cd "$FLUTTER_DIR" && flutter clean; }

build_rust_android() {
	local target triplet
	target=$(rust_target_for_abi "$ABI")
	triplet=$(vcpkg_triplet_for_abi "$ABI")
	[ -n "$target" ] || { echo "ABI không hỗ trợ: $ABI"; return 1; }
	[ -d "$VCPKG_ROOT/installed/$triplet" ] ||
		{ echo "Chưa có vcpkg deps cho $triplet — chạy: bash flutter/build_android_deps.sh $ABI"; return 1; }
	rustup target list --installed 2>/dev/null | grep -qx "$target" || rustup target add "$target" || return 1
	local feats=flutter
	case "$ABI" in arm64-v8a | armeabi-v7a) feats=flutter,hwcodec ;; esac
	if [ "$ABI" = x86 ]; then export CFLAGS="-DBROKEN_CLANG_ATOMICS" CXXFLAGS="-DBROKEN_CLANG_ATOMICS"; fi
	cd "$ROOT_DIR" || return 1 # cargo-ndk phải chạy ở repo root
	cargo ndk --platform 21 --target "$target" build --locked --release --features "$feats"
}

copy_lib_android() {
	local target src dst
	target=$(rust_target_for_abi "$ABI")
	src="$ROOT_DIR/target/$target/release/liblibrustdesk.so"
	dst="$FLUTTER_DIR/android/app/src/main/jniLibs/$ABI"
	[ -f "$src" ] || { echo "Không thấy $src"; return 1; }
	mkdir -p "$dst"
	cp "$src" "$dst/librustdesk.so" && ls -la "$dst/librustdesk.so"
}

build_rust_ios() { cd "$ROOT_DIR" && cargo build --locked --features flutter,hwcodec --release --target aarch64-apple-ios --lib; }
build_rust_macos() { cd "$ROOT_DIR" && cargo build --locked --features flutter; }

build_apk() {
	cd "$FLUTTER_DIR" &&
		flutter build apk "--$MODE" --target-platform "$(flutter_platform_for_abi "$ABI")"
}
apk_path() { echo "$FLUTTER_DIR/build/app/outputs/flutter-apk/app-$MODE.apk"; }
install_apk() {
	local apk
	apk=$(apk_path)
	[ -f "$apk" ] || { echo "Không thấy APK: $apk"; return 1; }
	echo "apk: $apk ($(du -h "$apk" | cut -f1))"
	"$ADB" -s "$DEVICE" install -r "$apk"
}
launch_app() {
	"$ADB" -s "$DEVICE" logcat -c 2>/dev/null
	"$ADB" -s "$DEVICE" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 || return 1
	local n=0
	until [ -n "$("$ADB" -s "$DEVICE" shell pidof "$PKG" 2>/dev/null | tr -d '\r')" ]; do
		n=$((n + 1)); [ $n -gt 30 ] && { echo "App không lên được process"; return 1; }
		sleep 1
	done
	echo "pid: $("$ADB" -s "$DEVICE" shell pidof "$PKG" | tr -d '\r')"
	local id="" n2=0
	while [ -z "$id" ] && [ $n2 -lt 20 ]; do
		id=$("$ADB" -s "$DEVICE" logcat -d 2>/dev/null | grep -a "_appType:" | tail -1)
		[ -z "$id" ] && sleep 1
		n2=$((n2 + 1))
	done
	[ -n "$id" ] && echo "$id"
	"$ADB" -s "$DEVICE" logcat -d 2>/dev/null | grep -aE "FATAL EXCEPTION|beginning of crash" | tail -5
	return 0
}

# ===================================================================== main ===
if [ $USE_LAST = 1 ]; then
	[ -s "$HIST" ] || die "Chưa có lịch sử, chạy ./run_customize.sh để cấu hình lần đầu"
	IFS=$'\t' read -r _ PLATFORM MODE DEVICE DEVICE_NAME ABI RUNNER <"$HIST"
elif [ $INTERACTIVE = 1 ]; then
	menu
fi

: "${PLATFORM:=android}"
: "${MODE:=debug}"
: "${RUNNER:=$([ "$PLATFORM" = android ] && echo fast || echo flutter)}"

if [ -z "$DEVICE" ]; then
	DEVICE=$(list_devices | awk -F'\t' -v p="$PLATFORM" '$3==p{print $1; exit}')
	DEVICE_NAME=$(list_devices | awk -F'\t' -v p="$PLATFORM" '$3==p{print $2; exit}')
	[ -n "$DEVICE" ] || die "Không tìm thấy device nào cho platform $PLATFORM"
fi
[ -n "$DEVICE_NAME" ] || DEVICE_NAME=$(list_devices | awk -F'\t' -v d="$DEVICE" '$1==d{print $2; exit}')

STATE=$(mktemp -t rc_state)

# đếm số bước
TOTAL_STEPS=3 # preflight + device + pub get
[ $DO_CLEAN = 1 ] && TOTAL_STEPS=$((TOTAL_STEPS + 1))
if [ $SKIP_RUST = 0 ]; then
	TOTAL_STEPS=$((TOTAL_STEPS + 1))
	[ "$PLATFORM" = android ] && TOTAL_STEPS=$((TOTAL_STEPS + 1)) # copy .so
fi
if [ $SKIP_BUILD = 0 ] && [ "$RUNNER" = fast ]; then TOTAL_STEPS=$((TOTAL_STEPS + 1)); fi
[ "$RUNNER" = fast ] && TOTAL_STEPS=$((TOTAL_STEPS + 2)) # install + launch

printf '\n%s┌─ %s · %s · %s%s\n' "$C_B$C_CYN" "$PLATFORM" "$MODE" "$DEVICE_NAME" "$C_RST"
printf '%s│  runner: %s   log: %s%s\n' "$C_DIM" "$RUNNER" "${LOG#"$ROOT_DIR"/}" "$C_RST"
printf '%s└─%s\n' "$C_DIM" "$C_RST"

step "Kiểm tra môi trường" "THIẾU|flutter :" preflight
step "Chuẩn bị device" "device:|Boot AVD|Không có" resolve_device
IFS=$'\t' read -r DEVICE DEVICE_NAME ABI <"$STATE"

[ $DO_CLEAN = 1 ] && step "flutter clean" "Deleting|Cleaning" do_clean
step "flutter pub get" "Got dependencies|Resolving|Changed" pub_get

if [ $SKIP_RUST = 0 ]; then
	case "$PLATFORM" in
	android)
		step "Build librustdesk.so ($ABI)" "^ *(Compiling|Building|Finished|error)" build_rust_android
		step "Copy .so vào jniLibs/$ABI" "librustdesk.so" copy_lib_android
		;;
	ios) step "Build liblibrustdesk.a (aarch64-apple-ios)" "^ *(Compiling|Finished|error)" build_rust_ios ;;
	macos) step "Build lib Rust (macOS)" "^ *(Compiling|Finished|error)" build_rust_macos ;;
	web) : ;;
	esac
fi

if [ "$RUNNER" = fast ]; then
	[ $SKIP_BUILD = 0 ] && step "Build APK ($MODE, $ABI)" "Running Gradle|Built |> Task|error" build_apk
	step "Cài lên $DEVICE" "apk:|Performing|Success|Failure" install_apk
	step "Mở app & kiểm tra" "pid:|_appType:|FATAL" launch_app
fi

hist_add

printf '\n%s─── Tóm tắt ─── %s%s\n' "$C_B" "$(hms $((SECONDS - START_ALL)))" "$C_RST"
for s in "${SUMMARY[@]}"; do printf '  %s\n' "$s"; done
printf '%s  log đầy đủ: %s%s\n' "$C_DIM" "$LOG" "$C_RST"
if [ "$PLATFORM" = android ] && [ "$RUNNER" = fast ]; then
	ID_LINE=$("$ADB" -s "$DEVICE" logcat -d 2>/dev/null | grep -a "_appType:" | tail -1)
	[ -n "$ID_LINE" ] && printf '%s  %s%s\n' "$C_YLW" "$ID_LINE" "$C_RST"
	printf '%s  chạy lại nhanh: ./run_customize.sh --last%s\n' "$C_DIM" "$C_RST"
fi

if [ $DO_TAIL = 1 ] && [ "$PLATFORM" = android ] && [ "$RUNNER" = fast ]; then
	printf '\n%s─── logcat (%s) — Ctrl+C để thoát ───%s\n' "$C_B" "$PKG" "$C_RST"
	PID=$("$ADB" -s "$DEVICE" shell pidof "$PKG" | tr -d '\r')
	exec "$ADB" -s "$DEVICE" logcat --pid="$PID" -v brief
fi

if [ "$RUNNER" = flutter ]; then
	printf '\n%s─── flutter run -d %s --%s ───%s\n' "$C_B" "$DEVICE" "$MODE" "$C_RST"
	cd "$FLUTTER_DIR" || exit 1
	exec flutter run -d "$DEVICE" "--$MODE"
fi
