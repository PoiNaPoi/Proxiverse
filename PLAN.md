# แผนพัฒนา Reqnivo

อัปเดต: 27 ตุลาคม 2026

## 1. เป้าหมาย

พัฒนา Reqnivo ให้รองรับ workflow หลัก:

**Capture → Filter → Inspect → Mock/Edit/Repeat → Save/Share**

เน้นความสะดวกในการใช้งานจริง ความถูกต้องของข้อมูล และความลื่นของ native macOS app

เอกสารนี้รวบรวม roadmap ที่ตกลงไว้ พร้อมสถานะหลังงาน Map Local และ JSON editor ล่าสุด ไม่ได้หมายความว่าทุก phase เสร็จแล้ว และการบันทึกเอกสารนี้ไม่ได้เริ่ม implementation ระยะถัดไป

อัปเดต P2: ส่งมอบ implementation ของ structured filters/saved filters/pin/multi-selection และตรวจ automated regression/native benchmark แล้ว รายละเอียดและข้อจำกัดการตรวจรับอยู่ด้านล่าง

## 2. ข้อตกลงและข้อจำกัด

- รองรับ macOS 14+ / Apple Silicon ใช้ SwiftUI + AppKit และ bundled mitmproxy เดิม
- ไม่เขียน proxy engine ใหม่ และไม่สร้างแอป Windows/Linux/mobile ในแผนหลัก
- เริ่มจาก workspace, filters และ inspector ก่อนเครื่องมือขั้นสูง
- คง auto-start capture และ LAN enabled ตามพฤติกรรมเดิม แต่ไม่เปิด Mac system proxy อัตโนมัติ
- การติดตั้ง/trust CA หรือเปลี่ยนค่าที่ต้องใช้สิทธิ์ ต้องได้รับการยืนยัน ไม่ bypass certificate pinning ของแอปภายนอก
- Preview เป็นโหมดเริ่มต้น ส่วน full-body capture ในอนาคตต้อง opt-in
- Full-body ที่วางแผนไว้จำกัด **16 MiB ต่อ request body หรือ response body** และ **1 GiB ต่อ session รวม metadata/index/body**
- เมื่อถึง budget ต้องแจ้งสถานะ ไม่เก็บต่อแบบไม่จำกัด ไม่ลบ saved sessions เงียบ ๆ และไม่ทำให้ traffic จริงเสีย
- Network Extension, general-purpose scripting, CLI/MCP และ protocol ขั้นสูง ต้องผ่าน feasibility gate ก่อนรับเป็นงานส่งมอบ

### แยกขีดจำกัดปัจจุบันออกจากฟีเจอร์ในอนาคต

| ส่วน | สถานะ/ขีดจำกัด |
|---|---|
| Live traffic ใน UI | 10,000 rows |
| Engine event retention | 30,000 events |
| Preview disk budget | 128 MiB |
| Body preview | 256 KiB ต่อ message; body เกิน 1 MiB ใช้ streaming ตามพฤติกรรมปัจจุบัน |
| Map Local mock body | UTF-8 text หรือ file ไม่เกิน 8 MiB |
| JSON formatter ใน mock editor | Output ไม่เกิน 8 MiB; formatter ของ inspector คง budget 2 MiB |
| Syntax colors ใน mock editor | ลงสีเฉพาะ 256K UTF-16 code units แรก แต่เก็บ body เต็ม |
| Paused traffic | ไม่เกิน 32 flows |
| Full-body / durable sessions | ยังไม่ส่งมอบ; ตัวเลข 16 MiB / 1 GiB เป็นข้อกำหนดของ phase ในอนาคต |

## 3. สิ่งที่ทำแล้ว

### Workspace และตาราง traffic

- แยก Capture/Domains sidebar พร้อม retained counts และสถานะ listener/LAN/Mac proxy
- เลือก inspector ด้านล่างหรือด้านขวา และจัด Request/Response เคียงกันหรือบนล่างได้
- จำ layout, divider และขนาด/ลำดับคอลัมน์ โดยรักษา hosted panes เดิมไว้
- เปิดแอปแล้วเรียง ID จากมากไปน้อย ให้ request ล่าสุดอยู่บน
- คง selection และพฤติกรรมตามแถวบนสุดตามเงื่อนไขเดิม
- เพิ่ม API version handshake และ body capture states แบบ backward-compatible

### Map Local และ Breakpoints

- แยกหน้าจัดการกฎ Map Local ออกจาก Breakpoints
- แก้ layout ของหน้ากฎและจัด empty state ให้อยู่กึ่งกลางฝั่งขวา
- พิมพ์ mock body ได้โดยตรง หรือเลือก File mode รวมถึง binary ตามข้อจำกัดเดิม
- ค้นหา, duplicate, เปิด/ปิด, ลบ และเรียง priority ของกฎได้
- เก็บ draft แยกแต่ละกฎ สลับกฎหรือค้นหาแล้วข้อความไม่หาย
- มี Apply โดยไม่ปิดหน้าต่าง และ Save & Close
- Inline body บันทึกผ่าน managed mock files ไม่ส่ง body ทั้งก้อนใน control API
- คลิกขวา traffic → Map Local เติม matching fields, status, response headers และ Response Body ของแถวนั้น
- Prefill body เฉพาะข้อความที่มีข้อมูลยืนยันว่าจับได้ครบ ไม่ใช้ partial preview หรือ placeholder แทน body จริง
- กรณีโหลดรายละเอียดไม่ได้ หรือ body เป็น truncated/streamed/encoded/binary จะแจ้งให้ป้อนเอง

### JSON editor

- Headers และ JSON Body ใช้ชุดสีร่วมกับ inspector
- จัดรูปแบบ JSON ตอนเปิด body จาก capture/ไฟล์ โดยรักษาลำดับ key, escapes และ number lexemes
- มีปุ่ม Format JSON สำหรับจัดใหม่หลังแก้ พร้อมรายงานข้อผิดพลาดโดยไม่เขียนทับข้อความที่ผิดรูปแบบ
- มีเลขบรรทัดและลูกศรย่อ/ขยาย `{}` / `[]` รวมถึง Collapse All / Expand All
- Folding ซ่อนเฉพาะ glyph/layout ไม่ลบข้อความออกจาก text storage; copy และ save ยังคง body เต็ม
- Enter ย่อหน้าตามระดับ, Tab เพิ่ม 2 spaces และ Shift+Tab ลดย่อหน้า
- รองรับ Undo/Redo และ IME โดยไม่ reformat ทุก keystroke
- เปลี่ยนตัวอ่าน token ของ formatter ให้รองรับ string ยาวโดยไม่คืน JSON ที่เนื้อหาขาดหาย

### ผลตรวจล่าสุดที่บันทึกไว้

ผลจากการพัฒนาวันที่ **27 ตุลาคม 2026**:

- Swift suite ล่าสุดผ่าน **113 tests** (รวม parser, saved-filter persistence/error cases, selection/pin/retention และ native controls light/dark/resize); P0 เดิมผ่าน 87 tests
- Map Local/Breakpoint engine smoke test ผ่านครบทุกเคส
- Standalone engine HTTPS smoke (100 requests) ผ่าน
- Native UI + engine GUI smoke (100 requests) ผ่าน รายงานครบ 104 flows โดยไม่หลุด sync และเลือกแถว/กรองจริง (25 / 37 ตัวอย่าง) บน ephemeral ports
- P0 baseline แยกรันทีละชุด (engine 10,000, native burst 10,000, native paced 300 @ 10/s): filter end-to-end p95 ≈ 89.7 ms @ 10,000 rows (ผ่านเป้า 100 ms), selection-to-render p95 ≈ 251.6–254.0 ms (เกินเป้า 250 ms แบบหวุดหวิด; ~190–220 ms เป็น text layout), UI RSS ≈ 197 MB + engine ≈ 186 MB, preview disk ≈ 105 MiB
- Release app build และ ad-hoc signature verification ผ่าน
- P2 native burst 10,000 requests: retained/visible 10,000 จากทั้งหมด 10,004 flows, filter end-to-end p95 **92.2 ms** (52 samples; รวม structured AND/negation/type/path), selection-to-render p95 **229.8 ms** (25 samples), ไม่มี benchmark timeout; UI RSS ≈ 187 MB + engine ≈ 187 MB, preview disk ≈ 105.7 MiB
- P2 engine HTTPS smoke (100 requests) และ rules smoke ผ่าน; ยังไม่ตรวจ VoiceOver/การกด Cmd/Shift ด้วยมือสำหรับ controls ใหม่ และยังไม่ยืนยัน macOS 14/เครื่อง 8 GB หรือ frame hitches

## 4. สถานะ roadmap

| Phase | สถานะ | สิ่งที่ยังต้องปิด |
|---|---|---|
| P0 — Baseline & contracts | เสร็จตามเกณฑ์ตรวจรับ (มีข้อจำกัด) | ผลวัดอยู่ใน [docs/BASELINE.md](docs/BASELINE.md); selection-to-render p95 251–254 ms ยังเกินเป้า 250 ms; ยังไม่ได้ยืนยัน macOS 14 / RAM 8 GB และ scroll/frame hitches |
| P1 — Native workspace | เสร็จสมบูรณ์ (พร้อมสำหรับ P2/P3) | ปิด acceptance gaps: keyboard navigation, light/dark, VoiceOver, resize, domain/path/client navigation และ inspector continuity ครบแล้ว |
| P2 — Structured filters | ส่งมอบ implementation; automated gates ผ่าน | ยังต้องตรวจ VoiceOver/keyboard interactions ของ controls ใหม่ด้วยมือ และ macOS 14/เครื่อง 8 GB; ไม่ถือว่า native smoke แทน manual accessibility acceptance |
| P3 — Inspector expansion | ยังไม่เริ่มระยะหลัก | มีพื้นฐาน Headers/Body/JSON แล้ว; ยังขาด Summary/Query/Cookies/Raw/search และชนิดข้อมูลเพิ่มเติม |
| P4 — Capture storage | ยังไม่เริ่ม | Opt-in full-body และ durable storage |
| P5 — Sessions & exchange | ยังไม่เริ่ม | Save/open session, HAR และ CSV |
| P6 — Compose & Repeat | ยังไม่เริ่ม | Composer, Edit & Repeat และ Copy as cURL |
| P7 — Debug tools | ยังไม่เริ่มระยะหลัก | มีฐาน Map Local/Breakpoint/editor แล้ว; ยังขาด Map Remote, Rewrite, trace และ tools ใหม่ |
| P8 — Protocol inspectors | ยังไม่เริ่ม | WebSocket/SSE inspector และ protocol regressions |
| P9 — Overview & timing | ยังไม่เริ่ม | Dashboard, timing, waterfall และ Diff |
| P10 — Capture setup | ยังไม่เริ่มระยะหลัก | มี setup/recovery พื้นฐานแล้ว; ยังต้องทดสอบอุปกรณ์และเพิ่ม SSL/upstream controls |
| P11 — Quality & release | ยังไม่เริ่มระยะหลัก | Test matrix, performance acceptance, signing/notarization และ release readiness |
| P12 — Advanced feasibility | ยังไม่เริ่ม | พิสูจน์ความเป็นไปได้ก่อนกำหนด scope |

**ไม่ถือว่า P0/P1 หรือ roadmap ทั้งหมดเสร็จจากการที่ unit tests ผ่านหรือ build แอปได้**

## 5. งานแต่ละ phase และเกณฑ์ตรวจรับ

### P0 — Baseline และ data/API contracts

**ขึ้นกับ:** ไม่มี

- ทำ baseline ที่ reproducible แยก UI, engine และ storage work
- วัด selection-to-render จริง ไม่ใช้เฉพาะเวลา fetch/model processing
- ทดสอบ API/schema version, legacy fixtures และ body completeness states
- กำหนด RAM/CPU budgets จาก workload ที่เปรียบเทียบได้ก่อนงานที่กระทบ performance

**ตรวจรับ:** Tests เดิมผ่าน, old rules/flows ยังอ่านได้, benchmark เลือกแถวจริง และ automated checks ไม่แก้ system proxy/Keychain

**สถานะ (27 ตุลาคม 2026):** ผ่านเกณฑ์ตรวจรับครบ budgets บันทึกใน [docs/BASELINE.md](docs/BASELINE.md) ข้อที่ยังเปิดอยู่และไม่ถือว่าปิด: selection-to-render p95 เกินเป้า 250 ms เล็กน้อย (ต้องตัดสินใจแก้ layout ใน P3 หรือปรับเป้า), scroll/frame hitches, macOS 14 และเครื่อง RAM 8 GB

### P1 — Native workspace

**ขึ้นกับ:** P0

- ปิด acceptance gaps ของ workspace/layout persistence
- ตรวจ resize, keyboard navigation, light/dark และ VoiceOver
- เพิ่ม domain/path/client navigation เท่าที่มีข้อมูลจริงรองรับ
- แสดง Capture/LAN/Mac Proxy/CA เป็นคนละสถานะ ไม่ถือว่า engine running แปลว่า setup ครบ

**ตรวจรับ:** เปลี่ยน layout แล้ว selection/แท็บ/folding ไม่ reset, ไม่เปลี่ยน launch defaults และไม่มีปุ่มที่ดูใช้งานได้แต่ยังไม่มี implementation

### P2 — Structured filters และ navigation

**ขึ้นกับ:** P1

- Query model/parser และ filter chips สำหรับ host/path/method/status range/content type/state
- Include/exclude, saved filters, pin และ multi-selection
- รักษา free-text search เดิมและ context menu ที่ผูกกับ flow identity

**ตรวจรับ:** Invalid query แสดง error, การรวม filters มีนิยามชัด, sort/filter/retention ไม่ย้ายเป้าหมายของ selection และ exclude จากหน้าจอไม่กลายเป็น block network

**สถานะ (27 ตุลาคม 2026):** เพิ่ม typed query/parser + chips สำหรับ host/path/method/status range/response Content-Type/state, AND + include/exclude (ไม่มี OR/regex), คง free-text phrase เดิม และ invalid draft ใช้ effective query ล่าสุดที่ถูกต้อง เพิ่ม local versioned saved filters (ชื่อ/query/sidebar scope) แบบ atomic พร้อม apply/rename/update/delete, pin แบบชั่วคราวและ Cmd/Shift multi-selection ที่ยึด flow ID

Filter ซ่อน selection ได้โดยไม่ย้าย inspector; pin ยังเคารพ filters/retention และไม่ persist; auto-follow ทำงานเฉพาะ capture insert เมื่อเลือกแถวแรกหนึ่งแถวและไม่มี pin Context actions ใช้ snapshot ไม่ใช้ row index หลัง reload ไม่เพิ่ม network-blocking rules ส่วน summary เพิ่ม optional Content-Type แบบ backward-compatible

Automated tests/build/signature/engine/rules/native benchmark ผ่านตามผลด้านบน ดู [docs/BASELINE.md](docs/BASELINE.md) และ [README.md](README.md) สำหรับวิธีใช้ ยังไม่ยืนยัน manual VoiceOver/keyboard interaction ของ controls ใหม่

### P3 — Inspector expansion

**ขึ้นกับ:** P1

- เพิ่ม Summary, Query, Cookies, Headers, Pretty และ Raw
- Body search/highlight, Copy/Save ตามข้อมูลที่มีจริง
- แยก pending, empty, incomplete, unavailable และ error
- Bounded decompression/charset handling; เพิ่ม image/hex ตามชนิดและ budget
- แสดง timing เฉพาะค่าที่เก็บได้จริง; ไม่มีข้อมูลให้แสดง N/A

**ตรวจรับ:** Duplicate headers/query และ JSON lexemes ยังถูกต้อง, decoded preview ไม่เขียนทับ original bytes และไม่แสดง placeholder เป็น body ที่ครบ

### P4 — Bounded full-body capture และ durable storage

**ขึ้นกับ:** P3

- เพิ่ม opt-in full-body โดยใช้ bounded spool/tee ไม่เก็บทั้ง session ใน RAM
- พิสูจน์ engine hooks และ backpressure ก่อนรองรับ known/unknown-length, streamed, compressed และ binary bodies
- บังคับ 16 MiB/body และ 1 GiB/session รวม metadata/index พร้อม bounded write queues
- แยก saved-session lifecycle ออกจาก rolling previews และ Clear Display

**ตรวจรับ:** ทดสอบก่อน/เท่ากับ/เกิน cap จริง รวม concurrent streams, แจ้ง disk/budget/queue errors และไม่ทำให้ forwarding เสียหรือกล่าวว่าจับครบทั้งที่ไม่ครบ

### P5 — Sessions และ import/export

**ขึ้นกับ:** P4, P2

- Native versioned session manifest + assets; save/open/rename/delete
- เปิด saved session แบบ offline หลัง relaunch
- HAR 1.2 import/export และ CSV export
- ระบุ export scope: selected/filtered/all
- Redaction พร้อม preview ก่อนแชร์

**ตรวจรับ:** Round-trip ข้อมูลเท่าที่ format รองรับ, แสดง omitted/incomplete bodies, ปฏิเสธ malformed/path traversal/oversize imports และไม่แนบ CA private key

### P6 — Compose, Edit & Repeat และ Copy as cURL

**ขึ้นกับ:** P5

- Composer สำหรับ HTTP/HTTPS และ repeat จาก captured/imported request ที่ครบ
- ถ้าขาด request body ให้ disabled พร้อมเหตุผล หรือให้ใส่ใหม่อย่างชัดเจน
- กำหนด count/concurrency/cancel bounds ก่อนเพิ่ม repetition
- cURL quoting สำหรับอักขระพิเศษและ duplicate headers/query

**ตรวจรับ:** ส่งครั้งเดียวต่อคำสั่งโดยไม่มี recursive replay, TLS verification ยังเปิด และ response ที่ไม่ครบไม่บล็อก repeat เมื่อ request ครบ

### P7 — Rules workspace และ debugging tools

**ขึ้นกับ:** P4, P2

- Typed/versioned rule actions และ migration ของกฎเดิม
- Map Remote, declarative Rewrite, Allow/Block และ No Caching
- Latency/bandwidth controls, folders และ import/export rules พร้อม managed mocks
- Matched-rule trace และ phase/precedence ที่ตกลงก่อนลงมือ

**ตรวจรับ:** รักษาลำดับ request breakpoint → Map Local → response breakpoint ของกฎเดิม, framing/encoding/HTTP2 ถูกต้อง และไม่ทำให้ 32-paused limit หรือ streaming restrictions ถอยหลัง

Declarative Rewrite ไม่ใช่ general-purpose JavaScript scripting และไม่รันโค้ดจาก imported rules อัตโนมัติ

### P8 — WebSocket/SSE และ HTTP/2

**ขึ้นกับ:** P4

- WS/WSS inspector: direction/time/type/bytes และ connection state
- SSE event inspector พร้อม bounded history/search
- HTTP/2 multiplexing, cancel และ header regression fixtures

**ตรวจรับ:** Long-lived streams ไม่ทำให้ UI ค้างหรือเก็บข้อมูลไม่จำกัด, แจ้ง dropped/incomplete data และ Stop เก็บ resources ครบ; ยังไม่เปิด message mutation/replay จนทดสอบแยกผ่าน

### P9 — Overview, timing, waterfall และ Diff

**ขึ้นกับ:** P8, P2

- Overview สำหรับ counts/data/errors/top domains/slow requests พร้อม drill-down
- Timing ตาม metadata จริง รวม reused connections และ HTTP/2
- Multi-request waterfall, multi-summary และ bounded header/body Diff

**ตรวจรับ:** บอกชัดว่า metrics อ้าง live retained data หรือ saved session ไม่ใช้ retained rows แทน total history และไม่แต่งค่า DNS/TLS ที่ไม่ได้เก็บ

### P10 — Capture setup, SSL controls และ recovery

**ขึ้นกับ:** P1

- Onboarding/localhost/LAN และ simulator/iOS/Android guides
- Selective SSL proxying และ upstream proxy configuration หลังพิสูจน์ engine support
- Client/app attribution เฉพาะที่ทราบจริง; ไม่ทราบให้แสดง Unknown
- ทดสอบ port conflict, permission denial, network switch, crash และ relaunch recovery
- ตกลง credential storage ก่อนรองรับ upstream authentication

**ตรวจรับ:** Export เฉพาะ public CA, privileged operations ต้องยืนยัน, recovery ไม่เขียนทับค่าของแอปอื่น และ credentials ไม่รั่วลง logs/export

### P11 — Hardening และ release readiness

**ขึ้นกับ:** P6, P7, P9, P10

- Native/integration test matrix และ performance acceptance
- ตรวจ offline sessions, rules migration, Stop/Quit และ crash/data-loss cases
- ตรวจ bundle, resources, engine และ signature
- ทดสอบบน macOS 14 และ OS/อุปกรณ์ที่ทีมใช้จริง
- Developer ID/notarization และ install/uninstall/recovery ก่อนแจกวงกว้าง

**ตรวจรับ:** มีผลทดสอบจริงครบ matrix; ถ้าไม่มีเครื่องหรือ signing account ต้องระบุเป็น blocker ไม่กล่าวว่ารองรับ/notarize แล้ว

### P12 — Advanced feasibility gates

**ขึ้นกับ:** P11 สำหรับการยกระดับเป็นงานส่งมอบ

ประเมินแยกเป็น prototype ที่มีเกณฑ์ go/no-go:

1. Network Extension: entitlement, signing, routing coexistence และข้อจำกัดระบบ
2. Protobuf/gRPC: schema discovery, streaming และ bounded decoding
3. JavaScript scripting: isolation, CPU/time/memory limits, permissions และ error console
4. CLI/MCP: authenticated local interface, explicit authorization สำหรับ mutations/replay และ redaction
5. HTTP/3, custom DNS/remote devices ขั้นสูง และ Postman/OpenAPI ตาม engine/format ที่พิสูจน์ได้

**ตรวจรับ:** มีหลักฐานความเป็นไปได้และ scope ที่อนุมัติ ไม่ถือว่า phase นี้ผูกมัดให้ส่งมอบทุกข้อ และไม่รับรอง proprietary session compatibility

## 6. ลำดับการทำงานถัดไป

1. ติดตามข้อจำกัด P0 ด้าน OS/เครื่อง/frame hitches และ manual acceptance ของ controls P2 โดยไม่ถือว่าปิดจาก unit tests
2. **P2 implementation และ automated gates ผ่านแล้ว**; ทำ P3 ต่อได้ตาม prerequisite P1 โดยตรวจ manual P2 แยกให้ครบ
3. ตรวจ workflow แรกให้ครบ: capture → filter หลายเงื่อนไข → sort/select → inspect/copy โดย state ไม่หาย
4. ทำ **P4** หลัง inspector แยก body states และข้อมูลจริงได้ชัดเจน
5. หลัง P4 ทำ P5, P7 และ P8 ตาม prerequisites; P6 ตาม P5
6. ทำ P9 เมื่อ protocol/timing metadata พร้อม และเดิน P10 ตามฐาน P1
7. รวม acceptance ใน P11 แล้วค่อยตัดสินงานขั้นสูงจาก P12

Dependency graph นี้ไม่บังคับให้ทุก phase รอเลขก่อนหน้าทั้งหมด แต่ต้องผ่าน prerequisites และเกณฑ์ตรวจรับของงานที่เกี่ยวข้องจริง

## 7. Validation และ performance gates

ใช้ focused tests ตามส่วนที่เปลี่ยนก่อน แล้วเลือกขยายการตรวจให้เหมาะกับขอบเขต:

```sh
./scripts/swift.sh test
./scripts/swift.sh build -c release
/usr/bin/python3 scripts/smoke-engine.py --count 100
/usr/bin/python3 scripts/smoke-rules.py
./scripts/build-app.sh
```

- Integration ใช้ local fixtures, temporary CA/data และ ports ที่ไม่ชนแอปจริง
- ไม่แก้ system proxy/Keychain ใน automated checks; ทดสอบสิทธิ์และอุปกรณ์จริงเป็น manual checks แยก
- หากแอปกำลังใช้ bundle ที่จะ build ทับ ต้องให้ผู้ใช้ Quit ก่อน ไม่ปิด process ของผู้ใช้เอง
- Regression ต้องครอบคลุม stale detail results, context-menu target, selection continuity, duplicate headers/query, JSON precision/escapes, folding/copy/save, empty/incomplete/encoded bodies และ missing assets
- Durable storage/import/migration ต้องมี atomic-write, corrupt-input และ data-loss cases

### Performance targets ที่ต้องพิสูจน์ ไม่ใช่ผลที่ผ่านแล้ว

- Reference: release build บน Apple Silicon/RAM 16 GB; ตรวจ macOS 14 และเครื่อง RAM 8 GB แยก
- Workloads: idle, 10,000-request burst, 10 requests/s จนครบ 10,000 requests, body หลายขนาด/encoding, HTTP/2 และ WS/SSE soak
- เป้าหมายตั้งต้น: p95 filter end-to-end **ไม่เกิน 100 ms ที่ 10,000 rows** หลังพ้น debounce
- เป้าหมายตั้งต้น: p95 selected-detail ถึงพร้อม render **ไม่เกิน 250 ms** สำหรับ local preview ไม่เกิน 256 KiB
- วัด UI main-thread stalls/scroll hitches และ RAM/CPU ของ UI + engine + storage workers แยกจาก model timing
- Memory ต้องหยุดโตเมื่อถึง retention bounds; pending I/O และ decoded output ต้อง bounded
- RAM/CPU budgets ยังต้องยืนยันจาก comparable baseline ใน P0 ไม่ลดเกณฑ์หรืออ้างว่าผ่านโดยไม่มีผลวัด

## 8. แหล่งอ้างอิงในโปรเจกต์

- [README และวิธีใช้งาน](README.md)
- [Baseline และข้อจำกัดการวัดเดิม](docs/BASELINE.md)
- [Capture model](Sources/Reqnivo/CaptureModel.swift)
- [Traffic table](Sources/Reqnivo/TrafficTable.swift)
- [Workspace layouts](Sources/Reqnivo/WorkspaceSplit.swift)
- [Rules UI](Sources/Reqnivo/RulesView.swift) และ [draft lifecycle](Sources/Reqnivo/RuleWorkspaceDraft.swift)
- [Rules และ managed mock files](Sources/Reqnivo/DebugRules.swift)
- [JSON presentation/formatter](Sources/Reqnivo/MessagePreview.swift)
- [Editable syntax component](Sources/Reqnivo/SyntaxTextEditor.swift)
- [Native JSON editing/folding layout](Sources/Reqnivo/JSONEditorTextView.swift)
- [Engine bridge](Sources/Reqnivo/Resources/bridge.py)
- [Regression tests](Tests/ReqnivoTests)
