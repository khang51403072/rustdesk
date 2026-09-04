# CUSTOM_CONFIG.md — cấu hình mặc định của bản Desk Remote X

> **File này mô tả code riêng của bản fork, không có trong RustDesk gốc.**
> Mọi thứ nói ở đây là phần chúng ta thêm vào. Khi merge upstream, đây là danh
> sách những chỗ cần để ý.
>
> Doc gồm năm phần: **mục 1–9** là cơ chế đặt giá trị mặc định, **mục 10** là
> rebrand phía Android, **mục 11** là theme thương hiệu, **mục 12** là lớp giao
> diện mobile mới, **mục 13** là bảng màu tách theo chế độ. Năm thứ khác chủ đề
> nhưng cùng bản chất — code riêng nằm rải trong file của upstream — nên gom
> chung một chỗ để rà.

## 1. Tóm tắt trong 30 giây

App cần một chỗ để đặt **giá trị mặc định** cho các tuỳ chọn — đặc biệt là nhóm
tuỳ chọn quyết định có nối thẳng P2P được hay không. Upstream đã có cơ chế đó,
nhưng file cấu hình phải được ký bằng khoá riêng của RustDesk nên bản fork không
dùng được.

Ta tái sử dụng đúng định dạng và đúng code xử lý của upstream, chỉ bỏ bước kiểm
chữ ký cho những nguồn do mình kiểm soát:

| Nguồn | Nằm ở đâu | Đổi giá trị cần gì |
| --- | --- | --- |
| `BUILTIN_DEFAULTS` | hằng số trong `src/custom_defaults.rs` | build lại app |
| `drx-defaults.json` | thư mục dữ liệu riêng của app trên máy | thay file, **không** build lại |

Cả hai chỉ ghi vào tầng **mặc định**. Người dùng vẫn đổi được mọi thứ trong
Settings.

## 2. Danh sách file đã thêm / đã sửa

| File | Loại | Nội dung |
| --- | --- | --- |
| `CUSTOM_CONFIG.md` | **mới** | Chính file này. |
| `src/custom_defaults.rs` | **mới** | Toàn bộ logic nạp cấu hình của fork. Không có gì của upstream trong file này. |
| `src/lib.rs` | sửa 2 dòng | Khai báo `pub mod custom_defaults;` kèm chú thích `[DRX CUSTOM]`. |
| `src/common.rs` | tách hàm | Thân `read_custom_client()` được dời sang `apply_custom_client_json()` để dùng lại. Logic không đổi. |
| `src/flutter_ffi.rs` | thêm 2 lời gọi | Gọi `custom_defaults::load()` ở `initialize()` và ở JNI `startServer`. |
| `flutter/android/.../MainService.kt` | sửa 4 chỗ | Rebrand thông báo foreground và notification channel — xem mục 10. |
| `flutter/android/.../FloatingWindowService.kt` | sửa 1 dòng | Rebrand menu cửa sổ nổi — xem mục 10. |
| `flutter/android/.../BootReceiver.kt` | sửa 1 dòng | Rebrand toast khi khởi động — xem mục 10. |
| `flutter/lib/drx_brand.dart` | **mới** | Bảng màu thương hiệu. Upstream không có file tương ứng — xem mục 11. |
| `flutter/lib/common.dart` | sửa ~12 dòng | `MyTheme` và `ColorThemeExtension` trỏ vào `DrxBrand` — xem mục 11. |
| `flutter/lib/mobile/pages/server_page.dart` | sửa 1 chỗ | Gradient header hộp thoại kết nối — xem mục 11.4. |
| `flutter/android/.../res/values/strings.xml` | sửa 1 dòng | Rebrand mô tả accessibility service — xem mục 10. |

Ngoài ra `drx-defaults.json.example` ở thư mục gốc là file mẫu cho mục 6, không
được app đọc.

Mọi chỗ sửa trong file của upstream đều được đánh dấu bằng chuỗi:

```
// ===== [DRX CUSTOM] =====
```

Tìm nhanh toàn bộ điểm can thiệp:

```bash
grep -rn "DRX CUSTOM" src/
```

## 2b. Đã kiểm chứng

Chạy thật trên Android emulator (arm64, `librustdesk.so` release, APK debug),
với `[options]` trong file cấu hình local **để trống** — nghĩa là người dùng chưa
từng chạm vào các công tắc này:

| Trạng thái | Use WebSocket | UDP hole punching | IPv6 P2P |
| --- | --- | --- | --- |
| Trước khi có module này | tắt | tắt | tắt |
| Sau, chỉ `BUILTIN_DEFAULTS` | tắt | **bật** | **bật** |
| Sau, thêm `drx-defaults.json` đặt `allow-websocket: "Y"` | **bật** | bật | bật |
| Sau khi xoá `drx-defaults.json` | tắt | bật | bật |

Xác nhận cả ba điều: mặc định built-in có tác dụng, file trên máy đè được lên
built-in, và xoá file thì quay lại đúng built-in.

## 3. Bốn tầng cấu hình của RustDesk

Mọi lần đọc một tuỳ chọn đều đi qua chuỗi này và **dừng ở tầng đầu tiên có giá
trị** (`Config::get_option` → `get_or(...)` trong `libs/hbb_common/src/config.rs`):

```
1. OVERWRITE_*        khoá cứng — công tắc trong app bị disable
2. file cấu hình máy  nơi lựa chọn của người dùng được ghi xuống
3. DEFAULT_*          ← chúng ta ghi vào đây
4. nhánh else Rust    hard-code, tầng cuối
```

- Tài liệu JSON dùng khoá `"default-settings"` để ghi vào tầng 3, và
  `"override-settings"` để ghi vào tầng 1.
- **Ta cố tình để `override-settings` rỗng.** Khoá cứng một tuỳ chọn mạng nghe
  hợp lý, nhưng nó tước mất đường thoát của người dùng ở mạng chặn gắt — họ sẽ
  không kết nối được bằng bất kỳ cách nào. Mặc định tốt + mô tả trong UI hiệu
  quả hơn.

### Một hệ quả cần biết

Hàm `is_option_can_save()` **không lưu** giá trị người dùng chọn nếu nó trùng
với giá trị ở tầng 3 — nó xoá khoá đi thay vì ghi. Kết quả đọc lại vẫn đúng (rơi
về tầng 3). Đây là hành vi của upstream và là hành vi mong muốn, không phải lỗi.

## 4. Định dạng tài liệu cấu hình

Giống hệt `custom.txt` của upstream, chỉ khác là không ký và không base64:

```json
{
  "default-settings": {
    "enable-udp-punch": "Y",
    "enable-ipv6-punch": "Y"
  },
  "override-settings": {}
}
```

Ngoài hai khoá trên, tài liệu còn nhận:

- `"app-name"` — đổi tên app hiển thị.
- Mọi khoá vô hướng còn lại → vào `HARD_SETTINGS` (ví dụ `conn-type`).

### Viết tên khoá thế nào

Trong JSON **luôn dùng dạng gạch nối**. Loader so khớp sau khi thay `_` thành
`-`, nên `image-quality` trong JSON sẽ khớp với hằng `image_quality` của Rust.

Khoá thuộc nhóm nào thì vào map nào — danh sách đầy đủ ở
`libs/hbb_common/src/config.rs`, mục `keys`:

| Nhóm hằng | Map mặc định | Ví dụ |
| --- | --- | --- |
| `KEYS_LOCAL_SETTINGS` (40) | `DEFAULT_LOCAL_SETTINGS` | `enable-udp-punch`, `enable-ipv6-punch`, `keep-screen-on`, `disable-floating-window` |
| `KEYS_SETTINGS` (59) | `DEFAULT_SETTINGS` | `allow-websocket`, `disable-udp`, `direct-server`, `approve-mode`, `custom-rendezvous-server` |
| `KEYS_DISPLAY_SETTINGS` (29) | `DEFAULT_DISPLAY_SETTINGS` | `image-quality`, `codec-preference`, `view-style` |
| `KEYS_BUILDIN_SETTINGS` (34) | `BUILTIN_SETTINGS` | `hide-websocket-settings`, `hide-network-settings` |

Khoá không nằm trong bốn danh sách trên sẽ bị ghi vào **cả bốn** map (hành vi
của upstream, nhánh `else` cuối `read_custom_client_advanced_settings`). Tránh
dùng khoá lạ.

### Quy ước giá trị bool

`option2bool()` trong `libs/hbb_common/src/config.rs` quyết định cách đọc:

| Tiền tố khoá | Mặc định khi rỗng | Nghĩa là |
| --- | --- | --- |
| `enable-…` | **bật** | phải ghi `"N"` mới tắt |
| `allow-…` | **tắt** | phải ghi `"Y"` mới bật |
| còn lại | **bật** | `"N"` để tắt |

## 5. Thứ tự nạp

`custom_defaults::load()` chạy theo đúng thứ tự này:

1. `BUILTIN_DEFAULTS` — hằng số trong binary.
2. `drx-defaults.json` trên máy — **đè lên** bước 1.

Hàm được gọi ở hai chỗ, vì trên Android `MainService` có thể khởi động server
trước khi Flutter engine gọi `initialize`:

- `src/flutter_ffi.rs` → `initialize()`
- `src/flutter_ffi.rs` → JNI `Java_ffi_FFI_startServer`

`load()` idempotent nên gọi hai lần không sao.

> **Lưu ý nếu sau này fork dùng blob đã ký:** hiện `load()` chạy **sau**
> `read_custom_client()`, nên cấu hình của ta sẽ đè lên blob. Điều này chấp nhận
> được vì fork không nạp blob nào. Nếu thay đổi, xem lại thứ tự trong
> `initialize()`.

## 6. File cấu hình theo từng đợt triển khai

### Đường dẫn

| Nền tảng | Đường dẫn |
| --- | --- |
| Android | `/data/data/com.carriez.flutter_hbb/app_flutter/drx-defaults.json` |
| iOS | thư mục dữ liệu app (`config::APP_DIR`) + `/drx-defaults.json` |
| macOS / Linux / Windows | cùng thư mục với file cấu hình `.toml` của app |

Không có file → chỉ `BUILTIN_DEFAULTS` áp dụng. Đây là trường hợp bình thường,
không ghi log lỗi.

### Đẩy file lên máy Android bằng adb (máy debug)

```bash
adb push drx-defaults.json /data/local/tmp/
adb shell "run-as com.carriez.flutter_hbb sh -c 'cp /data/local/tmp/drx-defaults.json app_flutter/'"
adb shell am force-stop com.carriez.flutter_hbb
```

Máy release không có `run-as`, phải đẩy qua MDM hoặc qua chính app.

### Kiểm tra đã nạp chưa

Cách chắc chắn nhất là **nhìn công tắc trong Settings**: đặt một khoá dễ thấy
(ví dụ `"allow-websocket": "Y"`), khởi động lại app, và xem mục “Use WebSocket”
đã bật chưa. Xoá file rồi khởi động lại thì nó phải trở về trạng thái cũ.

`log::info!` của `custom_defaults` chỉ hiện trong logcat khi **thư viện Rust được
build ở chế độ debug** — `android_logger::init_once` nằm sau
`#[cfg(debug_assertions)]` trong `flutter_ffi::initialize`. Với `librustdesk.so`
bản release (mặc định của `run_customize.sh`), lệnh dưới đây sẽ không ra gì kể cả
khi file đã nạp thành công:

```bash
adb logcat -s ffi | grep -i "DRX device config"
```

## 7. Bộ giá trị hiện tại và lý do

Đang đặt trong `BUILTIN_DEFAULTS`:

| Khoá | Giá trị | Lý do |
| --- | --- | --- |
| `enable-udp-punch` | `Y` | Đục lỗ NAT — điều kiện cần để nối thẳng khi cả hai bên sau NAT. Xem mục 8: mặc định của upstream đang tắt do một lỗi. |
| `enable-ipv6-punch` | `Y` | Đường nhanh nhất khi hai bên có IPv6, khỏi cần đục lỗ. Cùng lỗi như trên. |
| `allow-websocket` | `N` | Bật WebSocket là **mất hẳn P2P** — mọi phiên bị ép qua relay. Ghi rõ để chống một blob tương lai bật nó. |
| `disable-udp` | `N` | Tắt UDP là không đục lỗ được. |
| `enable-lan-discovery` | `Y` | Máy cùng LAN thấy nhau, khỏi qua máy chủ. |
| `enable-abr` | `Y` | Tự điều chỉnh bitrate — quan trọng khi buộc phải rơi xuống relay. |
| `disable-floating-window` | `N` | Giữ cửa sổ nổi để dịch vụ sống ở nền, và để mục "Keep screen on" không bị khoá. |
| `codec-preference` | `auto` | Để app tự chọn theo khả năng hai bên. |

### Đã cân nhắc nhưng **không** đặt

| Khoá | Vì sao không |
| --- | --- |
| `direct-server` = `Y` | Mở một cổng nghe trên thiết bị. Trong LAN tin cậy thì đây là cách nối thẳng tốt nhất, nhưng trên wifi công cộng nó tăng bề mặt tấn công. Nếu bật, nên bật kèm `whitelist` hoặc `id-whitelist` — quyết định theo từng đợt triển khai, để trong `drx-defaults.json` chứ không nhúng vào binary. |
| bất kỳ khoá nào trong `override-settings` | Xem mục 3. |

## 8. Bối cảnh: vì sao hai tuỳ chọn punch đang tắt

Upstream *có ý định* bật sẵn hai tuỳ chọn punch cho người dùng máy chủ công
cộng, ở `src/common.rs`:

```rust
pub fn get_local_option(key: &str) -> String {
    let v = LocalConfig::get_option(key);
    if key == keys::OPTION_ENABLE_UDP_PUNCH || key == keys::OPTION_ENABLE_IPV6_PUNCH {
        if v.is_empty() {
            if !is_public(&Config::get_rendezvous_server()) {
                return "N".to_owned();
            }
        }
    }
    v
}
```

Nhưng `is_public()` được viết cho **URL**:

```rust
pub fn is_public(url: &str) -> bool {
    let url = url.to_ascii_lowercase();
    url.contains("rustdesk.com/") || url.ends_with("rustdesk.com")
}
```

còn `get_rendezvous_server()` **luôn gắn `:port`** vào giá trị trả về. Chuỗi thật
là `rs-ny.rustdesk.com:21116`, không chứa `rustdesk.com/` và không kết thúc bằng
`rustdesk.com`. Nên `is_public()` **luôn trả `false`**, nhánh "máy chủ công cộng"
không bao giờ chạy, và hai tuỳ chọn mặc định **tắt cho tất cả mọi người**.

**Cấu hình của ta vòng qua lỗi này** mà không cần sửa nó: nhánh lỗi chỉ chạy khi
`v.is_empty()`. Đặt `enable-udp-punch = "Y"` ở tầng 3 làm `v` khác rỗng, nhánh bị
bỏ qua.

Vẫn nên sửa lỗi gốc và gửi ngược lên upstream — sửa 1 dòng:

```diff
-            if !is_public(&Config::get_rendezvous_server()) {
+            if !using_public_server() {
```

## 9. Cách thêm một mặc định mới

1. Tra khoá trong `libs/hbb_common/src/config.rs`, mục `keys` — xác nhận nó có
   trong một trong bốn `KEYS_*`.
2. Kiểm tra quy ước bool ở mục 4 để biết ghi `"Y"` hay `"N"`.
3. Thêm vào `BUILTIN_DEFAULTS` trong `src/custom_defaults.rs`, **kèm một dòng
   giải thích trong bảng ở mục 7 của file này**.
4. Nếu chỉ áp cho một đợt triển khai, đừng sửa binary — thêm vào
   `drx-defaults.json`.
5. Kiểm chứng: xoá dữ liệu app, mở lại, xem công tắc trong Settings đã đúng chưa.

## 10. Rebrand phía Android

> Phần này **không liên quan tới cấu hình**, nhưng cùng bản chất: đều là code riêng
> của fork nằm rải trong file của upstream và đều dễ mất khi merge. Cùng đánh dấu
> `[DRX CUSTOM]` nên `grep -rn "DRX CUSTOM"` ra hết một lượt.

### Vấn đề

Việc đổi tên app được làm ở phía Rust bằng một hằng số:

```rust
// libs/hbb_common/src/config.rs:72
pub static ref APP_NAME: RwLock<String> = RwLock::new("Desk Remote X".to_owned());
```

Nhưng **tầng Android không đọc hằng số đó**. Kotlin dựng thông báo, menu và toast
bằng chuỗi cứng của riêng nó, nên tên "RustDesk" vẫn lọt ra ở 5 chỗ người dùng
nhìn thấy. Nguồn chuẩn phía Android là:

```xml
<!-- flutter/android/app/src/main/res/values/strings.xml -->
<string name="app_name">Desk Remote X</string>
```

Đây cũng chính là resource mà `AndroidManifest.xml` dùng cho `android:label`, nên
mọi chỗ lấy từ đây sẽ không bao giờ lệch với tên trên launcher và trong các dialog
xin quyền của hệ thống.

### Đã sửa

| File | Trước | Sau | Người dùng thấy ở đâu |
| --- | --- | --- | --- |
| `MainService.kt:655` | `setContentTitle(DEFAULT_NOTIFY_TITLE)` | `setContentTitle(notifyTitle)` | Tiêu đề thông báo foreground, hiện suốt thời gian dịch vụ chạy |
| `MainService.kt:736` | `_title ?: DEFAULT_NOTIFY_TITLE` | `_title ?: notifyTitle` | Cùng thông báo trên, khi cập nhật nội dung |
| `MainService.kt:619` | `channelName = "RustDesk Service"` | `"$notifyTitle Service"` | Cài đặt → Ứng dụng → Thông báo |
| `MainService.kt:624` | `description = "RustDesk Service Channel"` | `"$notifyTitle Service Channel"` | Cùng chỗ trên |
| `FloatingWindowService.kt:311` | `translate("Show RustDesk")` | `getString(R.string.app_name)` | Menu của cửa sổ nổi |
| `BootReceiver.kt:39` | `"RustDesk is Open"` | `"${app_name} is Open"` | Toast khi máy vừa khởi động |
| `strings.xml:3` | `...when RustDesk screen sharing...` | `...when Desk Remote X screen sharing...` | Cài đặt → Trợ năng, đúng lúc người dùng bật Input control |

`notifyTitle` là một property nhỏ thêm vào `MainService`:

```kotlin
private val notifyTitle: String
    get() = getString(R.string.app_name)
```

Cần property vì `DEFAULT_NOTIFY_TITLE` là `const` ở cấp file — `const` không gọi
được `getString()`. Hằng số cũ vẫn giữ nguyên để hạn chế xung đột khi merge, chỉ
là không còn chỗ nào dùng nó.

### Cố ý **không** sửa

| Chỗ | Lý do |
| --- | --- |
| `MainService.kt:618` — `channelId = "RustDesk"` | Id của notification channel **không hiển thị**. Đổi id sẽ tạo channel mới và để lại channel cũ mồ côi trên máy đã cài, kèm nguy cơ mất thiết lập thông báo của người dùng. |
| `MainService.kt:560` — `"RustDeskVD"` | Tên virtual display, chỉ dùng nội bộ. |
| `strings.xml` không tham chiếu `@string/app_name` | Resource XML không nội suy resource khác, và `accessibility_service_description` được file cấu hình accessibility-service đọc trực tiếp nên phải là chuỗi tĩnh. Đây là chỗ **duy nhất** phải viết lặp tên app — sửa `app_name` thì nhớ sửa cả dòng này. |

### Cách rà lại sau này

```bash
grep -rn "RustDesk" flutter/android/app/src/main/ | grep -v "\[DRX CUSTOM\]" | grep -v "^.*// "
```

Sau khi sửa, những lần xuất hiện còn lại đều **không hiển thị cho người dùng** —
nếu grep ra thứ gì khác các dòng dưới đây thì có chỗ mới bị lọt:

| Còn lại | Loại |
| --- | --- |
| `MainService.kt` — `const val DEFAULT_NOTIFY_TITLE = "RustDesk"` | Hằng số không còn chỗ nào dùng, giữ lại để đỡ xung đột merge. |
| `MainService.kt` — `channelId = "RustDesk"` | Id nội bộ, xem bảng trên. |
| `MainService.kt` — `"RustDeskVD"` | Tên virtual display, nội bộ. |
| `FloatingWindowService.kt` — `idShowRustDesk` | Tên biến local. |
| `ffi.kt` — `System.loadLibrary("rustdesk")` | Tên file `.so`, không đổi được. |

### Đã kiểm chứng

Build lại APK, bật dịch vụ trên emulator:

| Chỗ | Trước | Sau |
| --- | --- | --- |
| Tiêu đề thông báo foreground | `RustDesk` | `Desk Remote X` |
| Tên notification channel (`dumpsys notification`) | `RustDesk Service` | `Desk Remote X Service` |
| Id notification channel | `RustDesk` | `RustDesk` (giữ nguyên, đúng ý) |

## 11. Theme thương hiệu

### 11.1 Vấn đề

Upstream để bảng màu thương hiệu dưới dạng hằng số literal nằm **giữa class
`MyTheme`** trong `flutter/lib/common.dart` — một file upstream sửa rất thường
xuyên. Sửa màu tại chỗ đồng nghĩa với conflict ngay giữa `MyTheme` mỗi lần
merge.

### 11.2 Cách làm

Toàn bộ palette dời sang **`flutter/lib/drx_brand.dart`** (file mới, upstream
không có). `MyTheme` chỉ còn *trỏ* vào đó. Nhờ vậy diff so với upstream chỉ là
vài dòng thay thế một-đổi-một, mỗi dòng có comment ghi giá trị gốc.

**Muốn đổi thương hiệu: sửa `drx_brand.dart`, không sửa gì khác.**

### 11.3 Bảng màu

| Hằng số | Giá trị | Upstream cũ | Dùng ở đâu |
| --- | --- | --- | --- |
| `primary` | `#2F9BFF` | `#0071FF` | `MyTheme.accent`, `MyTheme.button`, `colorScheme.primary/secondary` |
| `primaryDeep` | `#0B5FD0` | — | đầu gradient, trạng thái nhấn |
| `primaryLight` | `#5FB4FF` | `#00B6F0` | `MyTheme.idColor`, màu hyperlink |
| `darkBg` | `#12161C` | `#18191E` | nền trang, nền dialog |
| `darkSurface` | `#1A2029` | `#24252B` | card, ô nhập liệu |
| `darkSurfaceAlt` | `#222B36` | `#24252B` / `#121212` | menu, popup, outlined button |
| `darkHover` | `#263140` | `rgb(45,46,53)` | hover / pressed |
| `darkSelected` | `#1B3350` | `#3F3F3F` | `ColorThemeExtension.dark.highlight` |
| `darkBorder` | `#2C3543` | `#555555` | `ColorThemeExtension.dark.border` |
| `lightSurface` | `#EFF2F7` | `#EFEFF2` | `MyTheme.grayBg` |
| `lightBorder` | `#CFD6E0` | `#CCCCCC` | `MyTheme.border` |
| `muted` | `#94A3B3` | `rgb(148,148,148)` | `MyTheme.darkGray` |

Nhánh xám của upstream là xám trung tính; nhánh của ta ngả navy để khớp web
XSOFTS — mỗi bậc vừa sáng hơn vừa xanh hơn bậc trước, nhờ đó phân tầng đọc được
mà không cần đổ bóng.

`success`, `errorBannerBg`, `me`, `toast*` **cố ý giữ nguyên**: chúng mang ý
nghĩa ngữ nghĩa (thành công / lỗi / chính mình), không thuộc về thương hiệu.

### 11.4 Hai lỗi của upstream đã sửa luôn

1. **`colorScheme.primary` là `Colors.blue`** ở cả light lẫn dark, trong khi
   `secondary` mới là `accent`. Widget nào đọc `colorScheme.primary` thay vì
   `MyTheme.accent` (progress indicator, tay cầm bôi đen văn bản, con trỏ nhập
   liệu) sẽ lòi ra màu xanh mặc định của Material. Nay cả hai đều là `accent`.
2. **Gradient hồng–san hô** `#e242bc` → `#f4727c` ở header hộp thoại kết nối
   trong `lib/mobile/pages/server_page.dart`, chỏi hẳn với xanh thương hiệu. Nay
   dùng `gradientStart`/`gradientEnd`.

### 11.5 Mặc định dark

`BUILTIN_DEFAULTS` trong `src/custom_defaults.rs` thêm `"theme": "dark"`.

`theme` nằm trong `KEYS_LOCAL_SETTINGS` nên giá trị này rơi vào
`DEFAULT_LOCAL_SETTINGS`. Chuỗi tra cứu là
`OVERWRITE_LOCAL_SETTINGS` → config của người dùng → `DEFAULT_LOCAL_SETTINGS`
(`config.rs`, hàm `get_or`), nên **người dùng vẫn tự đổi sang Light hoặc Follow
system được**; lựa chọn của họ nằm ở tầng cao hơn.

> Chi tiết đáng lưu ý: khi người dùng chọn "Follow system", `changeDarkMode()`
> ghi giá trị `defaultOptionTheme`, mà biến này là `'system'` **chỉ khi**
> `isCustomClient` đúng — tức `APP_NAME != "RustDesk"`. Fork này đã đặt
> `APP_NAME = "Desk Remote X"` ngay trong `hbb_common`, nên điều kiện thoả và
> `'system'` được ghi tường minh, đè lên mặc định `dark` của ta. Nếu sau này có
> ai đổi `APP_NAME` về `"RustDesk"` thì tuỳ chọn "Follow system" sẽ **im lặng
> quay lại dark** — vì lúc đó nó ghi chuỗi rỗng và rơi xuống tầng mặc định.

### 11.6 Phần chưa động tới

| Hạng mục | Vì sao |
| --- | --- |
| Icon launcher, ảnh splash | Là asset ảnh, không phải giá trị theme. Nằm ở `flutter/android/app/src/main/res/mipmap-*`. |
| `TabbarTheme` | Chỉ dùng cho tab bar bản desktop, không xuất hiện trên mobile. |
| ~80 màu literal còn lại trong `lib/mobile/` | Phần lớn là overlay đen trong phiên điều khiển từ xa và chuột nổi — không mang tính thương hiệu. |
| Theme đọc từ config lúc chạy | Chưa làm. Nếu cần sau này: thêm khoá màu vào `drx-defaults.json`, đọc qua `mainGetLocalOption`, và xử lý reload `ThemeData` khi giá trị đổi. |

### 11.7 Cách rà sau khi merge upstream

```bash
cd flutter
# Còn sót literal xanh của upstream không?
grep -rn "0xFF0071FF\|0xFF2C8CFF\|0xFF00B6F0" lib/
# colorScheme có bị upstream đặt lại về Colors.blue không?
grep -n "primary: Colors.blue" lib/common.dart
# Nền dark có bị kéo về xám trung tính không?
grep -n "0xFF18191E\|0xFF24252B" lib/common.dart
```
Ba lệnh trên đúng ra phải **không ra kết quả nào** (trừ comment "was ...").

## 12. Lớp giao diện mobile mới

### 12.1 Ý tưởng

Thay vì chép `lib/mobile/pages/` rồi sửa, ta dựng một lớp giao diện **mới hoàn
toàn** trong `flutter/lib/drx/`. Thư mục này upstream không có nên vĩnh viễn
không conflict. Cả hai lớp cùng nằm trong một bản build; một cờ quyết định lớp
nào được dựng.

Lý do không clone: bản chép sẽ không nhận được thay đổi upstream, phải port tay
từng thứ, hai bản trôi xa dần. Lớp mới chỉ đọc model nên upstream sửa model là
hưởng luôn.

### 12.2 Cờ `ui`

| | |
| --- | --- |
| Khoá | `ui` — nằm ở **cấp cao nhất** tài liệu cấu hình, không nằm trong `default-settings` |
| Đổ vào | `HARD_SETTINGS` (nhánh "khoá còn lại" của `apply_custom_client_json`) |
| Đọc từ Dart | `bind.mainGetHardOption(key: 'ui')`, bọc trong `useDrxUi` ở `lib/drx/drx_ui.dart` |
| Giá trị | bất kỳ (mặc định `"drx"`) → UI mới · `"legacy"` → `HomePage` cũ |

Đặt ở cấp cao nhất là có chủ ý: khoá trong `default-settings` bắt buộc phải có
tên đăng ký sẵn trong `KEYS_*` của `hbb_common` — mà đó là submodule. Khoá lạ ở
cấp cao nhất thì không cần đụng submodule.

```bash
# lùi về UI cũ trên một máy, không cần build lại
echo '{"ui":"legacy"}' > drx-defaults.json   # đặt vào thư mục dữ liệu app
```

### 12.3 Bước 1 đã làm gì

Vỏ đã là của mình, **ruột vẫn là trang cũ**. Ba tab trỏ thẳng vào
`ConnectionPage`, `ServerPage`, `SettingsPage`. Từng tab sẽ thay dần ở các bước
sau.

| File | Loại | Nội dung |
| --- | --- | --- |
| `flutter/lib/drx/drx_ui.dart` | **mới** | Cờ `useDrxUi`. |
| `flutter/lib/drx/drx_home_page.dart` | **mới** | Vỏ: thanh tiêu đề, thanh dưới 3 tab, khung chứa trang. |
| `flutter/lib/main.dart` | sửa | Điểm chuyển duy nhất, dòng `home:`. |
| `flutter/lib/mobile/pages/settings_page.dart` | sửa 1 dòng | Báo cả hai vỏ khi cần dựng lại danh sách tab. |
| `flutter/lib/mobile/pages/server_page.dart` | sửa 1 chỗ | Nút chat của client: vỏ DRX mở bong bóng thay vì nhảy tab. |
| `src/custom_defaults.rs` | thêm 1 khoá | `"ui": "drx"`. |
| `flutter/lib/drx/drx_connect_page.dart`, `drx_share_page.dart` | **mới** | Ruột tab Kết nối và Chia sẻ màn hình (bước 2, 3). |
| `flutter/lib/drx/widgets/*.dart` | **mới** | `DrxIdCard`, `DrxCard`, `DrxPrimaryButton`, `DrxPeerTile`. |
| `flutter/lib/common/widgets/peer_card.dart` | thêm 1 hook | Mobile portrait rẽ sang `DrxPeerTile`; 3 chỗ `MyTheme.accent` chuyển sang `accentOf` (bước 4). |

### 12.4 Vì sao bỏ tab Trò chuyện

`ChatModel` đã có sẵn bong bóng chat kéo thả (`showChatIconOverlay()`), tự hiện
khi có tin nhắn đầu tiên (`chat_model.dart:373`). Code cũ **đã coi tab và bong
bóng loại trừ nhau**: `showChatIconOverlay()` thoát sớm nếu thanh dưới ở index 1
(`chat_model.dart:157`), và `home_page.dart:97` ẩn bong bóng khi vào tab chat.

Thêm nữa, tab chat là màn hình chỉ đọc khi không có phiên: ô nhập ở chế độ
`readOnly` nếu `serverModel.clients` không chứa `currentKey.connId`
(`chat_page.dart:85`).

### 12.5 Ba cái bẫy đã xử lý

**Ép kiểu `navigationBarKey`.** Chốt chặn ở `chat_model.dart:157` đọc
`navigationBarKey.currentWidget` rồi ép kiểu sang `BottomNavigationBar`. Vỏ DRX
**cố ý không gắn** khoá này — gắn vào là ném lỗi vì thanh dưới của ta không phải
`BottomNavigationBar`. Không gắn thì `currentWidget` là null, chốt bị bỏ qua, và
bong bóng hiện ở mọi tab. Đúng cái ta cần, lại không phải sửa `chat_model.dart`.

**Nút chat trong `server_page.dart:707`.** Nó gọi `bar.onTap!(1)` để nhảy sang
tab chat. Dưới vỏ DRX `bar` là null nên nút thành vô tác dụng. Đã rẽ nhánh theo
`useDrxUi`: vỏ mới mở thẳng `toggleChatOverlay()`.

**`refreshPages()` trong `settings_page.dart:1077`.** Gọi qua
`HomePage.homeKey` nên dưới vỏ DRX là no-op. Đã thêm `DrxHomePage.drxKey` và gọi
cả hai — chỉ một trong hai đang được dựng nên gọi cả hai là an toàn.

### 12.6 Ô peer trên mobile

`peer_card.dart` dùng chung với desktop, và hàm vẽ `makeChild()` nằm trên
`_PeerCardState` — lớp `State` **private**, không kế thừa cũng không override
được từ ngoài. Nên thay vì sửa thân hàm cho hai bố cục rất khác nhau, nhánh
mobile portrait **rẽ sớm** sang `DrxPeerTile`; hook trong file upstream chỉ 5
dòng.

Điều kiện là `isMobile && isPortrait`, không phải chỉ `isPortrait`: cửa sổ
desktop hẹp cũng báo portrait.

Khác gì so với hàng của upstream:

| | Upstream | DRX |
| --- | --- | --- |
| Màu ô nền tảng | `str2color(id + platform)` — **băm từ id máy** | Theo nền tảng; ngoại tuyến thì chuyển xám |
| Hình ô | Bo góc đều | Vát chéo góc dưới phải, nhắc lại nét X của logo |
| Chấm trực tuyến | `Colors.green` — 2.6 trên thẻ sáng | `successOf(context)` |
| Cỡ chữ | `titleSmall` (14) + body mặc định | 12.5 / 10.5 |

Màu băm từ id là chỗ đáng đổi nhất: nó ổn định theo từng máy nhưng **không mang
nghĩa gì** — hai máy Windows ra hai màu chẳng liên quan, nên danh sách không
quét mắt được.

### 12.7 Trang Cài đặt

`DrxSettingsPage` là trang mới hoàn toàn; `settings_page.dart` **không bị sửa
một dòng nào** và vẫn phục vụ vỏ cũ.

**Gom lại theo ý định, không theo module.** Nhóm `Settings` của upstream một
mình chứa 12 hàng chẳng liên quan — máy chủ relay, proxy, UDP, ngôn ngữ, công
tắc sáng/tối — nên tìm gì cũng phải đọc hết. Sáu nhóm mới: Kết nối · Chia sẻ
màn hình · Ứng dụng · Chất lượng hình ảnh · Nâng cao · Giới thiệu, cộng thẻ
"Thiết bị của bạn" ở đầu.

**Ẩn, không tắt.** 2FA và Recording biến khỏi màn hình theo yêu cầu. Giá trị đã
lưu **nguyên vẹn**: máy nào đang tự ghi phiên thì vẫn ghi, và giờ không tắt
được từ trong app. Muốn khoá hẳn thì đặt giá trị trong `custom_defaults.rs` rồi
ghim bằng `override-settings`.

**Vì sao không dùng lại gói `settings_ui`.** Gói đó không vẽ được thứ thiết kế
cần: phần Android của nó là dải kín chiều ngang không bo góc, còn thẻ bo góc chỉ
có ở `DevicePlatform.iOS` — kèm `CupertinoSwitch` và mũi tên iOS. Trên app
Android, công tắc Material quan trọng hơn cái bo góc, nên **không kiểu nào của
gói dùng được**. Widget riêng nằm ở `drx/widgets/drx_settings_row.dart`, và nhờ
đó có thêm: giá trị hiện bên phải hàng điều hướng, mô tả một dòng, và nhãn
"Rủi ro" cho công tắc duy nhất làm giảm mức bảo mật khi bật.

**Kiểm chứng không mất tính năng.** Đối chiếu tập khoá `kOption*` giữa hai
trang: đúng 4 khoá vắng mặt, đều thuộc phần bị ẩn.

```
kOptionAllowAutoRecordIncoming   kOptionEnableRecordSession
kOptionAllowAutoRecordOutgoing   kOptionEnableTrustedDevices
```

Mọi guard (`disabledSettings`, `hideSecuritySettings`, `outgoingOnly`,
`isIncomingOnly`, `isOptionFixed`) bê nguyên.

**Ba thứ phải dựng lại vì private.** `_DisplayPage`,
`_getPopupDialogRadioEntry`, và cặp `canStartOnBoot` /
`checkAndUpdateStartOnBoot` — lớp và method private không với tới từ thư viện
khác. Dựng lại với đúng khoá tuỳ chọn và danh sách giá trị. Còn lại gọi hàm cũ:
`showServerSettings`, `changeSocks5Proxy`, `showDeployDialog`,
`showLanguageSettings`, `showThemeSettings`, `changeWhiteList`,
`changeIdWhiteList`, `loginDialog`, `otherDefaultSettings()`.

Khoá dịch thêm mới: `Application`, `Image quality`, `Advanced`, `Risky`,
`Copy`, `drx-udp-punch-tip` — thêm vào cả 51 file `src/lang/`.

### 12.8 Link thương hiệu

`translate()` thay chuỗi `"RustDesk"` bằng tên app (`src/lang.rs`), nên tiêu đề
tự đổi thương hiệu. **URL không phải chuỗi dịch**, nên mọi `rustdesk.com` viết
cứng sống sót qua đợt rebrand và vẫn dẫn người dùng về trang upstream — kể cả
hộp thoại Giới thiệu.

Gom vào `drx/drx_links.dart`, thay ở 8 chỗ. Nhãn hiển thị suy ra từ chính URL
(`Uri.parse(url).host`) để hai thứ không lệch nhau được nữa.

Cố ý **không** thay:

| Nhóm | Vì sao |
| --- | --- |
| `rustdesk.com/docs/...` (7 chỗ) | Trỏ tới trang có thật và vẫn đúng cho client này. Đổi là biến trợ giúp đang chạy thành 404. |
| `admin.rustdesk.com`, `rs-ny.rustdesk.com`, API kiểm tra phiên bản | Mặc định hạ tầng, không phải thương hiệu. |
| `is_public()` — `src/common.rs:1089` | **Nhận diện máy chủ công cộng bằng chính domain đó.** Đổi là hỏng logic phân biệt self-hosted, thứ chi phối cả `_isUsingPublicServer` lẫn `should_use_raw_tcp_for_api`. |
| `libs/hbb_common` | Submodule. |
| `src/ui/*.tis` | Sciter UI, upstream đánh dấu deprecated. |

### 12.9 Chưa làm
- `chat_model.dart:157` vẫn còn chốt chặn index 1 (chưa cần gỡ, xem 12.5).
- Vỏ cũ trong `lib/mobile/pages/` giữ nguyên làm đường lui; chỉ xoá sau khi
  UI mới chạy thật một thời gian trên máy người dùng.

## 13. Bảng màu tách theo chế độ

### 13.1 Vấn đề gốc

`MyTheme.accent` là `static const` — **một giá trị dùng chung cho cả hai chế
độ**. Với chữ và icon, đó không phải lựa chọn tồi mà là chuyện **bất khả**:

| Yêu cầu | Ràng buộc độ sáng màu |
| --- | --- |
| Đạt 4.5 trên nền **trắng** | ≤ 0.183 |
| Đạt 4.5 trên nền **tối** `#0A1018` | ≥ 0.210 |

Hai khoảng **rời nhau**. Không màu nào — xanh hay không — thoả cả hai. Vì vậy
mọi màu dùng chung đều sẽ hỏng ở một trong hai chế độ. Thực tế đo được:

| Hằng số | Trên nền trắng |
| --- | --- |
| `MyTheme.accent` `#2F9BFF` | **2.9** |
| `MyTheme.darkGray` `#94A3B3` | **2.6** |
| `MyTheme.accent80` | **2.2** |
| `DrxBrand.success` `#22C55E` | **2.0** |

### 13.2 Cách sửa — ba tầng

**Tầng 1 · `ThemeData` dựng riêng cho từng chế độ.** Đòn bẩy lớn nhất: mọi
widget Material lấy màu từ theme đều được sửa mà không phải đụng chỗ gọi nào.

| Mục | Trước | Sau |
| --- | --- | --- |
| `colorScheme.primary/secondary` | `MyTheme.accent` | accent theo chế độ |
| `elevatedButtonTheme` | `MyTheme.accent` cho cả hai | `accentOnLight` / `actionGradientStart` |
| `switchTheme`, `radioTheme`, `checkboxTheme` | không có màu → rơi về `secondary` | nhận cờ `dark`, tô theo chế độ |
| `progressIndicatorTheme` | không có | thêm mới |
| `textSelectionTheme` | không có | thêm mới |
| `textTheme.labelLarge` | `accent80` | accent theo chế độ |

`switchTheme()` / `radioTheme()` giờ nhận tham số `bool dark`, và có thêm
`checkboxThemeOf(bool)`. Đây là lý do hàm đổi chữ ký.

**Tầng 2 · bộ hàm chọn theo chế độ trong `DrxBrand`.**
`accentOf(context)`, `mutedOf`, `identityOf`, `successOf`, `dangerOf`,
`warningOf` — đọc `Theme.of(context).brightness`.

Không dùng `ThemeExtension` mới: `themeMode` ánh xạ 1-1 sang `brightness`, nên
một hàm đọc brightness là đủ, ít gián tiếp hơn và không phải sửa `copyWith` /
`lerp` của `ColorThemeExtension` (code upstream).

**Tầng 3 · chuyển các chỗ gọi trực tiếp.** Chỉ những chỗ **vẽ trên nền sáng**:
`home_page.dart` (vỏ cũ), `file_manager_page.dart`, `connection_page.dart`,
`server_page.dart`.

### 13.3 Dải màu tối nới rộng

| | Trước | Sau | Tương phản |
| --- | --- | --- | --- |
| nền trang | `#12161C` | `#0A1018` | — |
| thẻ | `#1A2029` | `#1A2432` | so với nền: 1.09 → **1.22** |
| nổi | `#222B36` | `#28374A` | — |
| đường kẻ | `#2C3543` | `#3A4D64` | so với thẻ: 1.40 → **1.81** |

Ở 1.09 thì cạnh thẻ vô hình trên màn OLED; ở 1.40 thì đường kẻ trong thẻ không
thấy.

### 13.4 Cố ý chưa sửa

| Chỗ | Số lượng | Lý do |
| --- | --- | --- |
| `remote_page`, `view_camera_page`, `gesture_help` | 11 | Màn hình trong phiên, vẽ trên nền canvas tối. Accent trên nền tối là **đúng**, không phải lỗi. |
| Icon tiêu đề hộp thoại (`dialog.dart`) | 6 | Icon cần 3.0 chứ không phải 4.5; hiện đạt 2.9 — thiếu sát ngưỡng, và chúng đi kèm nhãn chữ đã đọc được. |
| Nền bong bóng chat (`chat_page.dart:162`) | 1 | Có thật, nhưng thuộc phần chat — sửa cùng lúc làm chat. |
| `peer_card.dart` | 3 | Bước 4 sẽ sửa file này. |
| Bản desktop | 33 | Bề mặt khác, chưa kiểm thử. Ngoài phạm vi. |

`MyTheme.accent` và `MyTheme.darkGray` **giữ nguyên giá trị** cho các chỗ trên,
nhưng đã kèm chú thích cảnh báo và chỉ sang `DrxBrand.accentOf(context)`.

## 14. Khi merge upstream

Các chỗ có thể xung đột:

| File | Rủi ro | Xử lý |
| --- | --- | --- |
| `src/common.rs` | Upstream sửa trong `read_custom_client` | Giữ phần tách hàm; đưa thay đổi của upstream vào `apply_custom_client_json`. |
| `src/flutter_ffi.rs` | Upstream sửa `initialize()` | Đảm bảo `custom_defaults::load()` vẫn chạy **sau** khi `APP_DIR` được đặt. |
| `src/lib.rs` | Danh sách module | Giữ lại dòng `pub mod custom_defaults;`. |
| `flutter/android/.../*.kt`, `strings.xml` | Upstream sửa thông báo hoặc menu | Giữ lại `notifyTitle` / `getString(R.string.app_name)`; rà lại bằng lệnh grep ở cuối mục 10. |
| `libs/hbb_common/src/config.rs` | Upstream đổi tên khoá hoặc `KEYS_*` | Đối chiếu lại `BUILTIN_DEFAULTS`; khoá không còn tồn tại sẽ bị ghi vào cả bốn map. |
| `flutter/lib/common.dart` | Upstream sửa `MyTheme` / `ColorThemeExtension` | Nhận thay đổi của upstream rồi trỏ lại vào `DrxBrand`; rà bằng ba lệnh grep ở mục 11.7. |
| `flutter/lib/main.dart` | Upstream sửa cây widget gốc | Giữ nhánh `useDrxUi ? DrxHomePage() : HomePage()` ở dòng `home:`. |
| `flutter/lib/mobile/pages/server_page.dart`, `settings_page.dart` | Upstream sửa quanh chỗ ta rẽ nhánh | Giữ hai móc `[DRX CUSTOM]` ở mục 12.5. |
| `flutter/lib/common.dart` | Upstream sửa `lightTheme` / `darkTheme` | Giữ các mục theo chế độ ở mục 13.2. `switchTheme`/`radioTheme` đã đổi chữ ký. |
| `flutter/lib/common/widgets/peer_tab_page.dart` | Upstream sửa dải tab | Giữ `_drxTabIcon` và nhánh `isMobile` cho màu. |

Nếu upstream tự sửa lỗi `is_public` ở mục 8, cấu hình của ta vẫn đúng — chỉ là
lúc đó nó trở thành dư thừa cho hai khoá punch, không gây hại.
