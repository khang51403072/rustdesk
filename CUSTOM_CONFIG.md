# CUSTOM_CONFIG.md — cấu hình mặc định của bản Desk Remote X

> **File này mô tả code riêng của bản fork, không có trong RustDesk gốc.**
> Mọi thứ nói ở đây là phần chúng ta thêm vào. Khi merge upstream, đây là danh
> sách những chỗ cần để ý.
>
> Doc gồm hai phần: **mục 1–9** là cơ chế đặt giá trị mặc định, **mục 10** là
> phần rebrand phía Android. Hai thứ khác chủ đề nhưng cùng bản chất — code
> riêng nằm rải trong file của upstream — nên gom chung một chỗ để rà.

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

## 11. Khi merge upstream

Các chỗ có thể xung đột:

| File | Rủi ro | Xử lý |
| --- | --- | --- |
| `src/common.rs` | Upstream sửa trong `read_custom_client` | Giữ phần tách hàm; đưa thay đổi của upstream vào `apply_custom_client_json`. |
| `src/flutter_ffi.rs` | Upstream sửa `initialize()` | Đảm bảo `custom_defaults::load()` vẫn chạy **sau** khi `APP_DIR` được đặt. |
| `src/lib.rs` | Danh sách module | Giữ lại dòng `pub mod custom_defaults;`. |
| `flutter/android/.../*.kt`, `strings.xml` | Upstream sửa thông báo hoặc menu | Giữ lại `notifyTitle` / `getString(R.string.app_name)`; rà lại bằng lệnh grep ở cuối mục 10. |
| `libs/hbb_common/src/config.rs` | Upstream đổi tên khoá hoặc `KEYS_*` | Đối chiếu lại `BUILTIN_DEFAULTS`; khoá không còn tồn tại sẽ bị ghi vào cả bốn map. |

Nếu upstream tự sửa lỗi `is_public` ở mục 8, cấu hình của ta vẫn đúng — chỉ là
lúc đó nó trở thành dư thừa cho hai khoá punch, không gây hại.
