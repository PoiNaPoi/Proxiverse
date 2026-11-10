# Proxiverse

ข้อมูลแอปอยู่ใน `~/Library/Application Support/Proxiverse/` ตัวแปร environment ใช้คำนำหน้า `PROXIVERSE_` และไฟล์ Map Local ใช้รูปแบบ `Proxiverse.MapLocal`

แอป native macOS สำหรับดู HTTP/HTTPS traffic ของทีม ใช้ SwiftUI + AppKit และ mitmproxy ที่ bundle มาด้วย ไม่ต้องติดตั้ง Python บนเครื่องผู้ใช้

**สถานะ: ต้นแบบใช้งาน capture, Map Local และ breakpoint ได้** รองรับ import/export Map Local แล้ว แต่ยังไม่มี import/export session และกฎชนิดอื่น และยังต้องประเมิน RAM/CPU/ความลื่นบนเครื่องทีม

โค้ดและเอกสารที่เป็นของ Proxiverse ใช้ [MIT License](LICENSE); engine และ dependency ใช้ license ของแต่ละโครงการตาม [Third-party notices](THIRD_PARTY_NOTICES.md) ใช้เฉพาะระบบและข้อมูลที่ได้รับอนุญาตให้ทดสอบ อ่าน [ขอบเขตการใช้งาน](docs/AUTHORIZED_USE.md) และ [การเก็บข้อมูลและการลบ](docs/PRIVACY.md) ก่อน capture ข้อมูลจริง ตรวจรายการที่ยังต้องยืนยันก่อนเปิด public ใน [Public release review](docs/PUBLIC_RELEASE_REVIEW.md)

## เปิดใช้งาน

เปิด `dist/Proxiverse.app` ที่ build ไว้แล้ว หรือ build ใหม่บน Apple Silicon ที่มี Xcode:

```sh
./scripts/fetch-engine.sh
./scripts/build-app.sh
open dist/Proxiverse.app
```

โลโก้หลักของโปรเจกต์คือ [`images/Proxiverse-icon.png`](images/Proxiverse-icon.png) สคริปต์ build จะสร้าง `Proxiverse.icns` ทุกขนาดจากภาพนี้ เพื่อใช้กับไฟล์แอป, Dock และหน้า About

เป้าหมาย deployment คือ macOS 14+ / Apple Silicon; ทดสอบจริงในรอบนี้บน macOS 27.0.1 / RAM 16 GB ยังไม่ได้ทดสอบ macOS 14 หรือ Intel

1. เปิดแอปแล้วเริ่ม capture อัตโนมัติหนึ่งครั้ง ค่าเริ่มต้นสำหรับผู้ใช้ใหม่ใช้ localhost เท่านั้น (listener `127.0.0.1:9090`, control เฉพาะ `127.0.0.1:9091`) หากต้องการจับจากมือถือ ให้ Stop แล้วเปิด `Allow test devices on local network` ใน Capture Settings ก่อน Start Capture เพื่อใช้ listener `0.0.0.0` ค่าที่ผู้ใช้เดิมบันทึกไว้จะยังคงเดิม หากพอร์ตถูกใช้อยู่จะแสดงข้อผิดพลาด ให้เปลี่ยนพอร์ตใน Capture Settings แล้วกด Start Capture
2. ติ๊ก **Capture Mac Traffic** ที่ด้านล่าง sidebar เพื่อจับ HTTP/HTTPS ของแอปที่ใช้ system proxy ของ Mac เปิด–ปิดระหว่าง capture ได้ทันทีโดยไม่ล้าง log; เอาติ๊กออกเพื่อคืนค่า proxy เดิม หากหยุด capture อยู่ ค่าจะมีผลตอนกด Start Capture ครั้งถัดไป เลือก network service ที่ใช้งานได้ใน **Capture Settings** ขณะหยุด capture การเปลี่ยน proxy ต้องอนุมัติสิทธิ์ administrator ผ่าน macOS
3. HTTPS: สถานะ CA ใน sidebar ตรวจ trust บน Mac เครื่องนี้อัตโนมัติประมาณทุก 2 วินาที เมื่ออนุญาต trust ใน Keychain แล้วจะแสดง `HTTPS trusted on this Mac` (ไม่รวม trust ของโทรศัพท์หรือแอปที่มี trust store ของตัวเอง) กด **Install Certificate** บน toolbar หรือ **Capture Settings → Install on Phone / Emulator…** เพื่อเปิดตัวช่วยติดตั้ง CA (รายละเอียดด้านล่าง)
4. กด **HTTPS** บน toolbar เพื่อเลือกโดเมนที่จะถอดรหัส (รายละเอียดด้านล่าง) แล้วเลือก request ในตารางเพื่ออ่าน Request ฝั่งซ้าย และ Response ฝั่งขวา แต่ละฝั่งสลับ Headers/JSON (หรือ Body เมื่อไม่ใช่ JSON) ได้แยกกัน JSON จัดรูปแบบและแยกสีอัตโนมัติ กดลูกศรข้างบรรทัด `{` หรือ `[` เพื่อย่อ/ขยาย object หรือ array แต่ละฝั่งแยกกันได้ และคงสถานะเมื่อสลับแท็บ กด Copy JSON เพื่อคัดลอกข้อความครบทั้งก้อนแม้มีส่วนที่ย่ออยู่; ค้นหา traffic ได้จาก URL, method, status และ error
5. กด **Stop** เมื่อจบการจับ traffic หากแอปตั้ง Mac proxy ไว้ จะพยายามคืนค่าให้ และมี recovery record สำหรับเปิดแอปกลับหลัง crash

การเปลี่ยน Mac proxy ขอสิทธิ์ผ่าน Authorization Services และ SystemConfiguration ของ macOS โดยตรง แทนกล่องอนุญาตรัน AppleScript เดิม รูปแบบการยืนยันตัวตน (Touch ID หรือรหัสผ่าน) ขึ้นอยู่กับ macOS, บัญชี และความพร้อมของ Touch ID; ยังต้องตรวจ Touch ID บนเครื่องจริง การ build/test ผ่านไม่ได้ยืนยันว่าระบบแสดง Touch ID แล้ว หลัง build ใหม่ให้ปิดและเปิด Proxiverse ใหม่เพื่อโหลดโค้ดนี้

คลิกขวาที่ request → **Map Local…** เพื่อเปิดกฎใหม่พร้อมเติม host, path/query, method, status และ response headers จากแถวนั้น (เว้น headers เกี่ยวกับขนาด/encoding/connection ที่ไม่ควรนำมาใช้กับไฟล์ mock) แล้วพิมพ์ body ใน **Text / JSON** หรือสลับเป็น **File** เพื่อเลือกไฟล์ การแก้ไขจะบันทึกและใช้งานอัตโนมัติหลังหยุดแก้ประมาณ 0.5 วินาที

เมื่อเปิดแอป ตารางจะเรียง ID จากมากไปน้อยเป็นค่าเริ่มต้น ให้ request ล่าสุดอยู่บนสุด หากเลือกแถวบนสุดเพียงแถวเดียวและไม่มี pin เมื่อมีรายการ capture ใหม่ระบบจะเลือกแถวบนสุดตาม sort ปัจจุบันต่อไป การเปลี่ยน filter/sort/pin ไม่ทำให้ auto-follow เลือก request ใหม่ เลือกแถวอื่นหรือเลือกหลายแถวแล้วจะคง flow identities เดิมไว้

### ติดตั้ง CA บนโทรศัพท์และ emulator

เปิด **Install Certificate…** จากเมนูแอปหรือ toolbar โดยเริ่ม capture อย่างน้อยหนึ่งครั้งเพื่อสร้าง CA ของ Mac เครื่องนี้

- **Phone / Tablet:** เชื่อมต่อ Wi-Fi เดียวกับ Mac เปิด LAN capture แล้วตั้ง Wi-Fi HTTP proxy บนโทรศัพท์ตาม IP/port ที่หน้าต่างแสดง จากนั้นสแกน QR หรือเปิด `http://mitm.it` บนโทรศัพท์ เลือก platform เพื่อดาวน์โหลด CA ของ capture นี้ iPhone/iPad ต้องติดตั้ง profile ใน Settings → General → VPN & Device Management แล้วเปิด full trust ใน General → About → Certificate Trust Settings
- **iOS Simulator:** เปิด simulator ใน Xcode กด Refresh เลือกเครื่อง แล้วกด **Install & Trust CA** แอปใช้ `xcrun simctl keychain <UDID> add-root-cert` กับเครื่องที่เลือกเท่านั้น การตั้ง proxy แยกจากการติดตั้ง cert: ติ๊ก Capture Mac Traffic ระหว่าง capture หรือกำหนด Mac HTTP/HTTPS proxy เป็น `127.0.0.1:<proxy port>` เอง ไม่ต้อง rebuild แอปที่ทดสอบเพื่อเพิ่ม cert
- **Android / Emulator (ADB):** ต้องมี Android SDK Platform-Tools และอนุญาต USB debugging บนโทรศัพท์ หรือเปิด emulator ก่อน กด Refresh เลือกเครื่อง แล้วกด **Install CA Automatically** สำหรับเครื่องที่มี root ADB แอปติดตั้งผ่าน Android TrustedCertificateStore และอ่าน cert กลับมาตรวจสอบ โดย debug emulator จะเรียก `adb root` ให้เอง หากเป็นโทรศัพท์ไม่มี root หรือ Google Play emulator image ให้ใช้ **Copy CA & Open Settings** แทน แอปส่ง public CA ไปที่ `Download/Proxiverse-CA.cer` แล้วเปิด Security Settings ให้เลือก Install a certificate → CA certificate ด้วยตัวเอง ชื่อเมนูขึ้นกับ Android รุ่นนั้น สถานะ “copied” ยังไม่ได้หมายถึงติดตั้งหรือ trust สำเร็จ

Android emulator มาตรฐานใช้ proxy `10.0.2.2:<proxy port>` พร้อมเปิด LAN capture ส่วนเครื่องจริงใช้ LAN IP ของ Mac แอปค้นหา ADB จาก `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `~/Library/Android/sdk`, PATH และตำแหน่ง Homebrew

แอป Android ที่ target Android 7+ โดยทั่วไปต้องตั้ง Network Security Configuration ของ debug build ให้ trust user CAs และ rebuild/reinstall debug app เมื่อแก้ configuration การติดตั้ง CA ไม่ข้าม certificate pinning ของแอป การติดตั้งอัตโนมัติบน Android เป็น **user CA** ไม่ใช่ system CA; ลบได้ผ่าน Settings ตามปกติ ไม่ต้อง restart emulator แต่ควรเปิดแอปที่ทดสอบใหม่ถ้ายังใช้ trust cache เดิม หน้าต่างนี้ไม่แก้ trust store ของ Mac หรือ system CA ของ Android ให้ ลบ CA จากอุปกรณ์เมื่อทดสอบเสร็จ

ตัวติดตั้ง Android เป็น DEX ขนาดเล็กที่ bundle ไปกับแอป ไม่ต้องติดตั้ง APK เพิ่ม และใช้ native `TrustedCertificateStore` สำหรับจัดการชื่อไฟล์/hash collision และตรวจสอบ cert หลังติดตั้ง ใช้ internal Android API จึงอาจไม่รองรับ Android/OEM บางรุ่นและจะแสดง error เมื่อยืนยันผลไม่ได้ หากแก้ source ใน `scripts/android/InstallCertificate.java` ให้รัน `./scripts/build-certificate-helper.sh` (ต้องมี JDK 17+ และ Android SDK Build-Tools) แล้ว build แอปใหม่ ผู้ใช้แอปไม่ต้องติดตั้ง JDK

ทดสอบติดตั้งจริงแบบ opt-in (คำสั่งนี้ติดตั้ง CA ของ Mac ลง emulator ที่ระบุ และรันซ้ำเพื่อตรวจการติดตั้งซ้ำ):

```sh
PROXIVERSE_CERT_TEST_EMULATOR=emulator-5554 ./scripts/swift.sh test --filter DeviceCertificateTests
```

อ้างอิง: [mitmproxy certificate setup](https://docs.mitmproxy.org/stable/concepts/certificates/), [Apple certificate trust](https://support.apple.com/en-us/102390), [Android Network Security Configuration](https://developer.android.com/privacy-and-security/security-config)

### Structured filters, saved filters และ selection

ช่องค้นหารองรับข้อความเดิมจาก URL/method/status/error และ structured query เช่น:

```text
host:api.test path:/v1 method:GET status:400-499 type:json -state:pending
```

- ทุกเงื่อนไขรวมแบบ **AND** กับ sidebar scope; `-field:value` คือ exclude จากหน้าจอเท่านั้น ไม่ block network
- `host` เท่ากันทั้งชื่อ, `method` และ `state` เท่ากันทั้งค่า; ไม่สนตัวพิมพ์ใหญ่/เล็ก
- `path` ค้นหา substring ของ percent-encoded path พร้อม query; `type` ค้นหา substring ของ **response Content-Type จริง** ไม่เดาจาก URL หรือ request headers
- `status` ใช้ค่า 100–599 หรือช่วง inclusive เช่น `200-299`; `state` ใช้ `pending`, `complete`, `error`, `paused-request`, `paused-response`
- ค่า missing ไม่ผ่าน positive predicate แต่ผ่าน exclude ของ predicate นั้น เช่น pending ไม่มี status และ capture เก่าอาจไม่มี Content-Type
- ค่าเว้นวรรคใช้ double quotes และ escape quote/backslash ด้วย `\"` / `\\` เช่น `path:"/a?name=hello world"`; ข้อความล้วนยังค้นหาทั้ง phrase เดิม และข้อความใน mixed query เป็นอีกหนึ่งเงื่อนไข AND
- ไม่มี OR/วงเล็บ/regex; unknown field, value ว่าง, range ผิด หรือ quote ไม่ครบแสดง error และยังใช้ **query ล่าสุดที่ถูกต้อง** ประเมิน traffic รวมถึงรายการใหม่ ไม่ apply เงื่อนไขบางส่วน
- กด **Add Filter** หรือคลิกขวา request → **Include/Exclude** เพื่อเพิ่มเงื่อนไข; chips กดสลับ include/exclude หรือลบได้ ขณะ query ผิดให้แก้ข้อความหรือล้างก่อน
- **Save… / Saved Filters** เก็บชื่อ + query + sidebar scope ใช้ซ้ำ/rename/update/delete ข้าม relaunch ได้ บันทึกแบบ atomic ใน `traffic-filters.json` ใต้ application data directory (`PROXIVERSE_DATA_DIR` หากกำหนด); ไม่เก็บ traffic, sort หรือ pin และไม่ overwrite ไฟล์ corrupt อัตโนมัติ
- ใช้ **⌘คลิก / Shift+คลิก** เลือกหลายแถว; inspector แสดง primary request ไม่ใช่ multi-summary พร้อมจำนวนที่เลือกและจำนวนที่ถูกซ่อนด้วย filter
- Selection ยึด flow ID: sort ไม่เปลี่ยนเป้าหมาย, filter ซ่อนได้โดย inspector ยังแสดง primary เดิมและคืน highlight เมื่อกลับมา; retention ล้างเฉพาะ IDs ที่ถูก evict หาก primary ถูกลบเลือกจาก selection ที่ยังเหลือ ไม่เลือก flow อื่นแทน กด **Deselect All** เพื่อล้างรวม hidden selection
- คลิกขวา → **Pin Selected / Unpin Selected** เรียง pinned group ก่อน และใช้ sort ปัจจุบันภายในแต่ละกลุ่ม แถวที่ pin มี `★`; หากคลิกแถวใน selection ใช้ selected IDs snapshot หากคลิกแถวนอก selection ใช้เฉพาะแถวนั้น **Map Local…** ยังใช้ clicked-flow snapshot เท่านั้น
- Pin ไม่ข้าม filters/rolling retention 10,000 rows, ไม่เก็บ body เพิ่ม และไม่คงข้าม relaunch; Clear Display หรือเริ่ม capture ใหม่ล้าง pin/selection แต่ไม่ลบ saved filters

ID ในตารางเป็นเลขลำดับ request ต่อ capture เริ่มจาก 1 และคงเดิมเมื่อกรองหรือเรียงข้อมูล ชี้ที่ช่อง ID เพื่อดู UUID ของ flow กดหัวคอลัมน์ ID, Method, Status, Source, Host, Path, Time หรือ Size เพื่อเรียง และกดซ้ำเพื่อกลับทิศทาง ค่าไม่ทราบ/กำลังรอจะอยู่ท้ายตาราง การเรียงไม่เปลี่ยน request ที่เลือกหรือแท็บใน inspector

คอลัมน์ **Source** แสดง **Map Local** เมื่อ response ใช้ข้อมูลจากไฟล์ mock สำเร็จจริง ทั้งโหมด File และ Text / JSON; แถวอื่นแสดง `—` (ชี้เพื่อดูรายละเอียด) หากไฟล์ mock อ่านไม่ได้หรือ request ถูกยกเลิกก่อนใช้งาน จะไม่แสดงป้าย Map Local ข้อมูลเก่าที่ไม่มีสถานะแหล่งที่มายังอ่านได้โดยไม่คาดเดาจากกฎปัจจุบัน

### Workspace

- **Sidebar**:
  - **Capture**: `All Traffic` พร้อมจำนวน retained requests ใน rolling buffer
  - **Domains & Paths**: แต่ละ Domain สามารถกางดู Path ย่อยที่จับได้จริง พร้อมตัวนับจำนวน request ในแต่ละ path
  - **Clients**: แยกตามที่อยู่ IP ของเครื่องต้นทางที่ส่งคำขอเข้ามาจริง (เช่น `127.0.0.1` หรือ LAN IP) และแสดง `Unknown` สำหรับข้อมูลที่ไม่มี client attribution
  - **Setup Statuses**: แสดง 4 สถานะแยกกันอย่างอิสระ: Listener (Capture), LAN access, Mac system proxy และ CA certificate generation status โดยไม่ถือว่า listener ทำงานแปลว่าตั้งค่าครบแล้ว
- เมนู **Workspace Layout**: เลือก inspector ด้านล่าง/ด้านขวา และเลือก Request/Response เคียงกัน/บนล่างได้ โดยคง pane เดิมไว้เพื่อรักษาแท็บ Headers/JSON และ JSON folding แม้จะเปลี่ยน layout หรือเปลี่ยนแถวที่เลือก
- เมื่อยังไม่ได้เลือก request จะแสดงข้อความ **Inspect a request** เต็มพื้นที่ inspector โดยไม่แสดงแผง Request/Response หรือปุ่ม Headers/Body ซ้อนอยู่ด้านหลัง
- จำ layout, ตำแหน่ง divider และขนาด/ลำดับคอลัมน์เมื่อเปิดใหม่; กด **⌘F** เพื่อไปช่องค้นหา, กด **Escape** เพื่อล้างการค้นหา และเลื่อนลูกศรขึ้น/ลงในตารางเพื่อ inspect traffic ทันที
- รองรับ Light Mode และ Dark Mode อย่างลื่นไหล พร้อม VoiceOver / Accessibility labels ครบทุกองค์ประกอบสำคัญ

Control API ใช้ schema version 1 จาก `/health` และ message มี `captureState` (`complete`, `truncated`, `streamed`, `encoded`, `binary`) เพื่อแยกข้อมูลจริงออกจาก preview ที่ถูกละไว้ ข้อมูลเก่าที่ไม่มีฟิลด์เหล่านี้ยัง decode ได้; การไม่มี `captureState` ไม่ใช่หลักฐานว่า body ครบ

## เลือกโดเมนที่จะถอดรหัส HTTPS

- ค่าเริ่มต้นยังไม่ถอดรหัส HTTPS ทุกโดเมน รวมถึงเมื่อเปิด settings รุ่นเก่า ทราฟฟิก HTTP ยังจับตามปกติ
- กด **HTTPS** บน toolbar หรือ **Capture Settings → HTTPS Decryption…** เพื่อจัดการเฉพาะโดเมนที่เคยกด Enable จากหน้าหลัก โดเมนที่พบใน traffic จะไม่ถูกเพิ่มเอง เอาติ๊กออกเพื่อปิดแต่เก็บรายการไว้ หรือกดถังขยะเพื่อลบและปิดการถอดรหัสสำหรับ connection ใหม่ ค่าเปิด–ปิดและการลบจำไว้เมื่อเปิดแอปใหม่
- รายการที่ส่งผ่าน TLS จะแสดง method `CONNECT` และ status **Encrypted** เมื่อเลือกจะแสดงแผง **Encrypted connection** พร้อมโดเมน สถานะ และปุ่ม **Enable Decryption**; หลังเปิดจะแนะนำให้เชื่อมต่อ client ใหม่ หรือคลิกขวาที่โดเมนใน sidebar เพื่อเปิด–ปิดได้
- จับคู่ hostname ตรงตัวทุกพอร์ต เช่น `api.example.com` ไม่รวม `sub.api.example.com` ไม่รองรับ wildcard, URL หรือ path
- ค่ามีผลกับ TLS connection ใหม่โดยไม่ต้องหยุด capture ให้ปิด connection/เปิดแอป client ใหม่แล้วส่ง request อีกครั้ง connection และข้อมูลเก่าจะไม่เปลี่ยนย้อนหลัง
- โดเมนที่ไม่เปิดจะส่งข้อมูลเข้ารหัสเดิมโดยไม่อ่าน headers/path/body รายการที่เห็นเป็นข้อมูล connection เท่านั้น ไม่ใช่ HTTP response ที่อ่านได้; Map Local และ breakpoint ใช้ได้กับ HTTPS ที่เปิดถอดรหัสแล้ว
- โดเมนที่เปิดยังต้อง trust CA ของ Proxiverse แยกจากการเลือกโดเมน การเลือกนี้ไม่เปลี่ยนการตั้งค่า upstream certificate verification

ทดสอบ HTTPS แบบเฉพาะคำสั่ง โดยไม่แก้ system proxy/Keychain (เปิด `example.com` ในหน้า HTTPS ก่อน หากต้องการดู headers/body):

```sh
curl --noproxy '' --proxy http://127.0.0.1:9090 \
  --cacert "$HOME/Library/Application Support/Proxiverse/ca/mitmproxy-ca-cert.pem" \
  https://example.com
```

## Simulator, Emulator และมือถือจริง

- Mac: ตั้ง HTTP/HTTPS proxy เป็น `127.0.0.1:9090` หรือใช้การตั้งค่าอัตโนมัติในแอป
- iOS Simulator: trust CA ใน Simulator; routing อาจใช้ Mac system proxy ได้ แต่ต้องยืนยันกับเวอร์ชัน Simulator ที่ทีมใช้
- Android Emulator ของ Android Studio: โดยทั่วไปเข้าถึง Mac ผ่าน `10.0.2.2:9090`; เปิด `Allow test devices on local network` แล้วตั้ง proxy บน emulator ให้ตรงกับสภาพแวดล้อม
- มือถือจริง: ใช้เครือข่ายที่เข้าถึง Mac ได้ เปิด LAN ในแอป ตั้ง Wi-Fi HTTP proxy เป็น LAN IP ของ Mac และ port 9090 ตรวจ firewall หากต่อไม่ได้
- โหมด LAN เปิด listener บนทุก IPv4 interface ของ Mac; ใช้เฉพาะเครือข่ายทดสอบที่ไว้ใจได้ รุ่น baseline ยังไม่มี allowlist รายอุปกรณ์ ส่วน control API ยังคงอยู่บน loopback และต้องใช้ token
- iOS/iPadOS: หลังติดตั้ง CA ให้เปิด full trust ใน Certificate Trust Settings
- Android/app debug build: กำหนด Network Security Config ให้เชื่อถือ CA สำหรับ debug ตามนโยบายของแอป
- Certificate pinning ต้องจัดการใน debug build ของทีม แอปนี้ไม่ได้ bypass pinning ของแอปภายนอก

หากต้องการข้ามการตรวจ certificate ของเซิร์ฟเวอร์สำหรับ debug: **Stop Capture** → **Capture Settings** → เปิด **Skip server certificate verification (debug only)** → **Start Capture** ตัวเลือกนี้ข้ามการตรวจ certificate และ hostname ของปลายทาง HTTPS ที่ถอดรหัสในรอบ capture นั้น จึงไม่ต้องเลือก custom CA ค่าเริ่มต้นสำหรับผู้ใช้ใหม่ปิดตัวเลือกนี้และตรวจ certificate ตามปกติ ส่วนค่าที่บันทึกไว้เดิมยังคงเดิม สามารถปิดสวิตช์ก่อนเริ่ม capture เพื่อกลับไปตรวจ certificate ได้ โดยสถานะ capture จะแจ้งเมื่อกำลังข้ามการตรวจ

สำหรับเซิร์ฟเวอร์ที่ใช้ CA ภายในองค์กรและขึ้น `self-signed certificate in certificate chain`: กด **Stop Capture** → **Capture Settings** → **Choose CA File…** แล้วเลือกไฟล์ PEM CA/bundle ที่ได้จากทีม IT → **Start Capture** อีกครั้ง แอปเก็บสำเนา CA ไว้ใน data directory และรวมกับชุด CA มาตรฐานของ engine โดยยังตรวจ certificate และ hostname ตามปกติ ใช้ **Replace CA File…** เพื่อเปลี่ยน bundle หรือ **Remove Custom CA** เพื่อกลับไปใช้ชุดมาตรฐาน การเลือกไฟล์นี้ไม่ติดตั้ง CA ลง Keychain หรืออุปกรณ์ และเป็นคนละส่วนกับ **Show Public CA Certificate** ที่ใช้ให้ client เชื่อถือ proxy

ขั้นตอน CA อ้างอิง [mitmproxy certificates](https://docs.mitmproxy.org/stable/concepts/certificates/)

## Map Local และ Breakpoint

เปิด **Map Local** หรือ **Breakpoints (N)** ใน toolbar เพื่อจัดการกฎแยกกัน หากเลือก traffic ไว้จะเติม host/path/method จากรายการนั้นให้ แต่ละหน้าจะแสดงและบันทึกเฉพาะกฎของตัวเอง การเพิ่ม/ลบ/เรียงกฎฝั่งหนึ่งไม่ลบหรือเปลี่ยนกฎอีกฝั่ง

- **Add** ใน Map Local: กำหนด **Matching** (name, host, path รวม query, method), **Response** (status 200–599, delay 0–60000 ms และ headers ที่กดขยายได้) และ **Body**; `*` แทนข้อความใดก็ได้, `?` แทนอักขระหนึ่งตัว (รองรับ wildcard แบบ shell รวม `[abc]`); host ไม่แยกตัวพิมพ์ ส่วน path แยกตัวพิมพ์ กฎที่ตรงและเปิดใช้อันแรกจากบนลงล่างชนะ
- **Text / JSON**: พิมพ์หรือวาง response body ได้โดยตรง รองรับ UTF-8 ไม่เกิน 8 MiB พร้อมตัวนับ bytes; เมื่อเปิด body ที่เป็น JSON จาก capture/ไฟล์ จะจัดรูปแบบด้วย indent 2 spaces โดยรักษาลำดับ key, escape และค่าตัวเลขเดิมไว้ การเปิดดู body อย่างเดียวไม่เขียนไฟล์ใหม่ เมื่อแก้ข้อความจะบันทึกอัตโนมัติเป็น managed mock file ไม่แนบ body ทั้งก้อนใน control API
- คลิกขวา traffic → **Map Local…** จะเติม Response Body ของแถวนั้นให้ด้วย เมื่อ capture ระบุว่าเป็นข้อความที่ครบถ้วน หากถูกตัด เป็น stream, encoded/binary หรือ capture เก่าไม่มีข้อมูลยืนยันความครบถ้วน จะแจ้งเตือนและให้ป้อน body เอง ไม่เอา placeholder/preview ที่ไม่ครบไป mock
- **JSON editor**: มีเลขบรรทัด กดลูกศรข้างเลขบรรทัดเพื่อย่อ/ขยาย `{}` และ `[]` หรือใช้ **Collapse All / Expand All** การพับซ่อนเฉพาะการแสดงผล การ copy/save ยังได้ body เต็ม และเริ่มแก้ไขจะขยายกลับให้อัตโนมัติ กด Enter เพื่อย่อหน้าตามระดับ, Tab เพิ่ม 2 spaces, Shift+Tab ลดย่อหน้า และ **Format JSON** เพื่อจัดใหม่โดย undo ได้ ไม่จัดใหม่ทุก keystroke จนเคอร์เซอร์กระโดด หาก JSON ไม่ถูกต้องจะแจ้งข้อผิดพลาดและคงข้อความเดิมไว้; ยัง mock plain text, empty body หรือ JSON ที่ตั้งใจให้ผิดได้ การจัดรูปแบบจำกัด output ตามขนาด mock 8 MiB เพื่อป้องกันการขยายจาก nesting ที่สูงเกินไป
- ช่อง **Response headers** และ **Text / JSON body** มี syntax colors ชุดเดียวกับ inspector รองรับ undo/redo และ IME และเลื่อนข้อความภายในแต่ละช่องได้เมื่อเนื้อหายาวเกินกรอบ โดยไม่เลื่อนฟอร์มด้านนอกแทน; เพื่อไม่ให้ body ขนาดใหญ่ทำให้การพิมพ์หน่วง จะลงสีเฉพาะ 256K UTF-16 code units แรก แต่บันทึก body เต็มตามขีดจำกัด 8 MiB
- **File**: เลือกไฟล์ response ไม่เกิน 8 MiB ได้เหมือนเดิม รวม binary; กฎเก่ายังใช้ File mode การสลับไฟล์ UTF-8 เป็น Text / JSON จะโหลดข้อความมาแก้ได้ หากเป็น binary จะแสดงข้อผิดพลาดและคง File mode
- **จัดการหลาย endpoint**: ค้นหาจาก name/host/path/method/status, เปิดปิดแต่ละกฎด้วย checkbox, ใช้ **Duplicate** เพื่อทำสำเนาถัดจากต้นฉบับ และ ↑/↓ เปลี่ยน priority เมื่อช่องค้นหาว่าง หมายเลข # เป็นลำดับจริง ไม่เปลี่ยนตามการค้นหา ถ้า duplicate ใช้เงื่อนไขเดียวกับต้นฉบับ ต้องแก้เงื่อนไข/ลำดับหรือปิดต้นฉบับเพื่อให้สำเนาถูกเลือก
- สลับกฎหรือค้นหาแล้วข้อความ body ที่ยังไม่บันทึกไม่หาย หน้าต่าง Map Local และ Breakpoint Rules เปิดแยกจากหน้าหลัก จึงดู log ระหว่างแก้ได้ ทุกการแก้ไขรวมถึง checkbox จะบันทึกและอัปเดต engine อัตโนมัติหลังหยุดแก้ประมาณ 0.5 วินาที โดยไม่ต้อง restart capture หาก validation ไม่ผ่านจะแสดงข้อผิดพลาดและใช้กฎที่บันทึกสำเร็จล่าสุดต่อไป ปุ่ม **Close** ปิดหน้าต่างโดยการแก้ล่าสุดยังถูกบันทึก
- Map Local ใช้กับ request body ที่ทราบขนาดไม่เกิน 1 MiB; streaming upload ที่ตรงกฎจะถูกยกเลิกพร้อมแสดงเหตุผล แทนการส่งต่อไปปลายทาง (client บางตัวอาจรอจน timeout)
- แอปคัดลอกไฟล์เข้า `~/Library/Application Support/Proxiverse/mock-files/` แล้ว จึงย้ายไฟล์ต้นฉบับได้ หากแก้ต้นฉบับให้เลือกไฟล์ใหม่เพื่ออัปเดต mock; ถ้าไฟล์ managed หายจะตอบ 502
- **Add** ใน Breakpoints: เลือกหยุด request, response หรือทั้งสองขา กฎจะบันทึกและเริ่มใช้โดยอัตโนมัติ รายการในตารางจะแสดง `Ⅱ REQ` / `Ⅱ RES` เปิด **Breakpoints (N)** → **Paused Traffic (N)** → **Edit…** เพื่อแก้ URL/method/headers/body ของ request หรือ status/headers/body ของ response แล้วกด **Continue**; **Cancel Request** ยกเลิก flow ส่วน **Close Editor** ปิดหน้าแก้ไขโดยยังหยุดรออยู่ หน้าต่าง **Paused Traffic** แยกจากหน้าหลัก และการปิดหน้ารายการไม่ปล่อย request ที่หยุดอยู่
- Body แก้ได้เฉพาะ UTF-8 text/JSON ที่ครบและไม่เกิน 256 KiB รวมถึง JSON แบบ `Transfer-Encoding: chunked` ที่ไม่บีบอัด โดยรอรับ body ครบก่อนหยุดให้แก้; encoded/binary/streamed body คง bytes เดิม หากคาดว่าจะ stream จะหยุดก่อนส่ง headers และแก้ body ไม่ได้ สำหรับ chunked JSON ที่เกินขีดจำกัด buffer ของ engine (1 MiB) จะหยุดก่อนเริ่ม stream เพื่อไม่ให้ข้อมูลไหลผ่านก่อนกด Continue
- ลำดับทำงานคือ request breakpoint → Map Local (จับคู่ URL หลังแก้ request) → response breakpoint กฎเปลี่ยนแล้วใช้กับการจับคู่ครั้งถัดไป รายการที่หยุดอยู่ต้อง Continue/Cancel เอง; กด **Stop** หรือปิดแอปจะยกเลิกทั้งหมด เมื่อมี 32 รายการหยุดรอแล้ว รายการที่ตรงเพิ่มจะถูกยกเลิก
- เลือกกฎหลายรายการในหน้าต่าง Map Local ด้วย **⌘-click** หรือ **Shift-click** แล้วเลือก **Export… → Export Selected (N)…** เพื่อส่งออกเฉพาะรายการที่เลือกในไฟล์เดียวตามลำดับเดิม หรือกด **Delete** เพื่อลบทุกรายการที่เลือกและบันทึกอัตโนมัติ หรือเลือก **Export All…** เพื่อส่งออกทุกกฎตามลำดับเป็นไฟล์ Proxiverse JSON พร้อม response body (รวม binary และข้อความที่ยังรอบันทึก) จึงย้ายไปเครื่องอื่นได้โดยไม่ต้องคัดลอกไฟล์ mock แยก
- **Import…** เพิ่มกฎต่อท้ายของเดิมและบันทึกอัตโนมัติ รองรับ Proxiverse JSON และ Proxyman macOS `.config` ที่มี `mapLocalData` รวมถึง JSON tree ของ Map Local แบบแยก กฎจากโฟลเดอร์จะถูกคลี่ตามลำดับเดิมและคงสถานะปิดของโฟลเดอร์ไว้; กฎเครื่องมืออื่นใน backup จะไม่ถูกนำเข้า
- กฎ Proxyman ใช้ **URL pattern** และ **Include subpaths** ใน Matching เพื่อคง protocol/port/query ของ URL เดิม; หลาย HTTP methods แยกเป็นหลายกฎ รองรับ wildcard และ response ที่ฝังมาเป็น raw file หรือ HTTP message (status, headers, body) หากมี Regex, Directory, GraphQL, `FILE_URL` ภายนอก หรือไฟล์ response ไม่ได้ฝังมา จะยกเลิกทั้งชุดพร้อมแจ้งสาเหตุ ก่อนเปลี่ยนรายการกฎ
- Import รองรับไฟล์ไม่เกิน 256 MiB, response body ไม่เกิน 8 MiB ต่อกฎ และรวมกฎทุกชนิดได้สูงสุด 200 กฎ; Export เป็น format ของ Proxiverse สำหรับนำกลับเข้า Proxiverse
- กฎบันทึกใน `rules.json` และโหลดตอนเปิดแอปครั้งถัดไป การ Stop/Start หรือล้างรายการ traffic ไม่ล้างกฎ

การหยุด/ทำต่อใช้ [mitmproxy Flow API](https://docs.mitmproxy.org/stable/api/mitmproxy/flow.html) ส่วนการแก้ message ใช้ [HTTP API](https://docs.mitmproxy.org/stable/api/mitmproxy/http.html)

## การเก็บข้อมูลและข้อจำกัดต้นแบบ

- Metadata ฝั่ง UI จำกัด 10,000 แถว; engine เก็บ event ล่าสุดไม่เกิน 30,000 events และเก็บ live flow references เฉพาะขณะหยุดที่ breakpoint (ไม่เกิน 32 รายการ)
- Detail previews อยู่ใน `~/Library/Application Support/Proxiverse/captures/` จำกัดพื้นที่ 128 MiB; preview เก่าอาจถูกนำออกก่อน metadata หากเต็ม
- Body preview จำกัด 256 KiB ต่อ message; body เกิน 1 MiB ให้ engine stream ผ่านโดยไม่เก็บ body ทั้งก้อน การส่ง traffic จริงไม่ถูกตัดตาม preview
- รุ่นนี้ยังไม่แสดง body ที่บีบอัดหรือ binary; headers ยังตรวจได้ ข้อจำกัดนี้ต้องประเมินก่อนใช้แทน Proxyman เต็มรูปแบบ
- หลัง Stop ยังอ่าน preview ได้จนเริ่ม capture ใหม่หรือปิดแอป การเริ่ม capture ครั้งใหม่ล้าง preview เก่า รวมไฟล์ที่เหลือหลัง crash มี lock ป้องกันใช้ data directory เดียวกันพร้อมกัน
- CA private key อยู่เฉพาะ data directory ของเครื่อง ห้ามนำ private key ไปแชร์ให้ทีม ใช้ public `mitmproxy-ca-cert.pem` สำหรับติดตั้ง client
- `Clear Display` ล้างเฉพาะรายการ UI; ไม่ใช่คำสั่งลบข้อมูลบนดิสก์หรือ reset ตัวนับ engine
- WebSocket ส่งผ่านและเก็บเฉพาะ message ล่าสุดใน engine ผ่านการทดสอบ echo 20 messages แล้ว; ไม่มี message inspector และยังไม่ได้ทดสอบ soak test ของ WebSocket
- ไม่แก้ PAC, bypass list หรือบริการเครือข่ายอื่นนอกจาก service ที่เลือก; authenticated proxy เดิมจะถูกปฏิเสธเพื่อไม่ทำข้อมูล authentication สูญหาย
- ถ้า endpoint เดิมปิดอยู่และไม่มี server ค่า restore จะปิด proxy ให้; อาจเหลือ localhost ในช่อง server ที่ inactive ถ้าแอปอื่นแก้ proxy ระหว่างจับ traffic จะไม่เขียนทับ endpoint นั้น และเก็บ recovery record ไว้ให้ตรวจ
- App bundle นี้ใช้ development/ad-hoc signature ยังไม่ผ่าน Developer ID signing/notarization สำหรับแจกวงกว้าง

## ทดสอบและวัด baseline

```sh
./scripts/swift.sh test
/usr/bin/python3 scripts/smoke-engine.py --count 100
/usr/bin/python3 scripts/smoke-rules.py
/usr/bin/python3 scripts/smoke-https-decryption.py
/usr/bin/python3 scripts/smoke-engine.py --count 10000 --output .cache/engine-https-burst.json
/usr/bin/python3 scripts/smoke-engine.py --count 300 --rate 10 \
  --app dist/Proxiverse.app --output .cache/native-paced-baseline.json
```

สคริปต์ integration test สร้าง local fixture และ CA ชั่วคราว ตรวจ HTTPS โดยใช้ CA ของ test เฉพาะ engine/client ไม่แก้ trust store หรือ system proxy หากเปิดแอปจับ traffic อยู่ต้อง Stop ก่อนทดสอบ GUI เนื่องจากใช้ port 9090/9091

ชุดทดสอบ engine ตรวจ HTTPS body, streaming, encoded body, token authentication, ปฏิเสธ browser Origin, WebSocket echo 20 messages และ retention ของข้อมูล ส่วน GUI benchmark ใช้ local HTTPS fixture และสำเนา test CA ใน data directory ชั่วคราวของแอป เพื่อไม่ต้องติดตั้ง CA ลงระบบ ตัว native UI ถูกตรวจ HTTPS/HTTP2 แยกด้วย curl และ public CA ของแอป

รายงาน baseline ที่วัดได้อยู่ใน [docs/BASELINE.md](docs/BASELINE.md) มี raw JSON ให้ตรวจซ้ำ ค่า CPU จาก `ps` เป็น decaying average ของ macOS ไม่ใช่ interval CPU; เวลาประมวลผล model ไม่ใช่เวลา render frame ต้องใช้ Instruments และทดสอบ scroll ต่อก่อนสรุปว่าไม่กระตุก

## โครงสร้างและ engine

- `Sources/Proxiverse`: native UI, bounded traffic model, process lifecycle และ Mac proxy recovery
- `Sources/Proxiverse/Resources/bridge.py`: loopback API ที่มี bearer token, body preview storage และ parent watchdog
- `scripts`: fetch engine แบบ pin version/checksum, build `.app` และ integration/benchmark harness

UI poll metadata เป็นชุดทุก 250ms โดย decode นอก main actor; detail โหลดเมื่อเลือก ไม่ส่ง body ทุกแถวเข้า UI ตารางใช้ NSTableView และ reuse cell ส่วน engine เป็น subprocess เพื่อแยก lifecycle และไม่ embed Python ใน Swift process

Engine pin ไว้ที่ mitmproxy **12.2.3 macOS arm64**, ดาวน์โหลดจาก official distribution และตรวจ SHA-256 กับ code signature ใน build script ต้นฉบับ vendor ถูกเก็บครบทั้ง app รวม dependency notices ภายใน พร้อม [MIT license](vendor/mitmproxy-LICENSE.txt) ห้ามลบ notices เมื่อนำไปแจก

source ของ mitmproxy, ldap3 และ urwid พร้อม checksum อยู่ใน `vendor/third-party/` อ่าน [วิธีตรวจ source, build และเปลี่ยน engine ในสำเนาแอป](docs/ENGINE_SOURCE.md) สำหรับการแก้ไลบรารีและสร้าง engine ใช้เอง ขั้นตอนนี้แยกจาก engine ที่แอปเดิมใช้อยู่ และไม่ใช่การยืนยัน dependency ฝั่ง native/Rust ครบทั้งหมด

## งานช่วงถัดไปหลังประเมิน baseline

1. ตกลง RAM/CPU/UI latency budget จากเครื่องทีม และทดสอบ macOS 14 / RAM 8 GB
2. บันทึก/นำเข้า/ส่งออก session และกฎชนิดอื่น (Map Local รองรับแล้ว)
3. ทดสอบอุปกรณ์จริงและ system proxy recovery บนเครื่องทดสอบ ก่อนทำ signed/notarized build สำหรับทีม

### Persistent settings

- Pin domain, Proxy/Control port, LAN access, Mac capture, network service, TLS verification และตำแหน่ง Inspector/Request–Response บันทึกอัตโนมัติใน `~/Library/Application Support/Proxiverse/settings.json` (หรือ `PROXIVERSE_DATA_DIR` หากกำหนด) และโหลดกลับเมื่อเปิดแอป
- Layout เดิมจาก preferences จะย้ายมาไฟล์นี้เมื่อเปิดครั้งแรก ส่วน Pin แถว request ยังคงอยู่เฉพาะ session
- ลบเฉพาะ `Proxiverse.app` แล้วติดตั้งใหม่ด้วยบัญชี macOS เดิมจะใช้ข้อมูลเดิมได้ หากไม่ลบ Application Support ของแอป
