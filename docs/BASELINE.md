# Baseline

## P2 structured-filter acceptance — 27 ตุลาคม 2026

Release build บน Apple Silicon / RAM 16 GB / macOS 27.0.1; native benchmark รันแยกจาก engine/rules smoke ใช้ ephemeral ports และ temporary data/CA ไม่แก้ system proxy/Keychain ผู้ใช้ Quit แอปเดิมก่อน build bundle ใหม่

```sh
./scripts/swift.sh test
./scripts/build-app.sh
/usr/bin/python3 scripts/smoke-engine.py --count 100 --output .cache/p2-engine-smoke.json
/usr/bin/python3 scripts/smoke-rules.py
/usr/bin/python3 scripts/smoke-engine.py --app dist/Proxiverse.app --count 10000 --output .cache/p2-native-burst.json
```

- Swift suite **113 tests ผ่าน**; release build/ad-hoc signature verification, standalone HTTPS smoke (100 requests) และ rules smoke ผ่าน
- Workload: 10,000 requests + 4 fixture flows, retained/visible **10,000**; benchmark complete, 0 timeouts
- Filter workloads เดิม 5 แบบ + `method:GET status:200-299 -state:error`, `type:json -type:image`, `path:request=1 -host:excluded.test` และ sidebar domain/All ซ้ำ 5 รอบ รวม **52 end-to-end samples**
- Harness บังคับ native run ที่ count ≥ 10,000 ให้ visibleRows = 10,000 และ filter p95 ≤ 100 ms ไม่ใช้ model-only timing แทนเกณฑ์

| Metric | P2 ล่าสุด | เกณฑ์ |
|---|---|---|
| Filter end-to-end p50 / p95 | 52.7 / **92.2 ms** | p95 ≤ 100 ms — ผ่าน |
| Filter model-only p50 / p95 | 16.6 / 23.7 ms | ไม่ใช้แทน end-to-end |
| Selection-to-render p50 / p95 | 214.9 / **229.8 ms** (25 samples) | p95 ≤ 250 ms — ผ่านใน workload นี้ |
| UI RSS / engine RSS | 187.3 / 187.0 MB | แต่ละส่วน ≤ 250 MB |
| Preview disk / retained files | 105.7 MiB / 10,000 | ≤ 128 MiB |
| Process-tree peak RSS | 372.7 MB | RSS อาจนับ shared pages ซ้ำ |

รอบแรกก่อนแยก sidebar aggregation ออกจาก user filter path ได้ filter p95 115.0 ms ไม่ผ่าน จึงแก้ให้ refresh retained stats เฉพาะเมื่อ capture data เปลี่ยน ไม่คำนวณ path/client counts ใหม่ทุกครั้งที่แก้ query และข้าม table reload เมื่อ rows/pins ไม่เปลี่ยน โดยยังยกเลิก auto-follow ด้วย filter revision ผลวัดซ้ำได้ 99.9 ms และ 90.7 ms; final release หลังเพิ่ม sort-aware primary fallback ได้ 92.2 ms ไม่ปรับเกณฑ์ลงเพื่อให้ผ่าน

Model-only ใน P2 รวม compiled query matching แต่ไม่ทำ sidebar aggregation ซ้ำเมื่อกรอง ต่างจาก P0 ที่รวม sidebar ทุกครั้ง จึงต้องอ่านคู่กับ end-to-end แทนการเทียบ model-only โดยตรง ข้อจำกัดการวัด end-to-end เหมือนเดิม: หลัง debounce ถึง table apply/sort เสร็จ ไม่รวม cell drawing หรือ frame/scroll hitches

Tests เพิ่มครอบคลุม invalid draft/effective query, quoted round-trip, response Content-Type จริง/legacy missing metadata, atomic saved-filter CRUD/corruption/write failure, primary/hidden selection, retention/pin pruning, pinned sort, stale context/auto-follow และ native controls hosting ที่ light/dark/resize ผลโปรแกรมไม่ได้ยืนยันการใช้งาน VoiceOver/Cmd-Shift ด้วยมือ, macOS 14, เครื่อง 8 GB หรือ Instruments hitches; ผล selection-to-render ที่ดีขึ้นใน workload นี้ไม่ปิดข้อจำกัด P0 ทั้งหมด

Raw reports: [P2 native burst](benchmarks/p2-native-burst.json), [P2 engine HTTPS smoke](benchmarks/p2-engine-smoke.json)

---

## P0 comparable baseline — 27 ตุลาคม 2026

Release build บน Apple Silicon / RAM 16 GB / macOS 27.0.1 ยังไม่ได้ยืนยันบน macOS 14 หรือเครื่อง RAM 8 GB รันแต่ละชุด **ทีละชุด ไม่ซ้อนกัน** บน ephemeral ports (`PROXIVERSE_PROXY_PORT`/`PROXIVERSE_API_PORT`) พร้อม data directory/CA ชั่วคราว ไม่แตะ system proxy/Keychain และไม่ชนพอร์ต 9090/9091 ของแอปจริง

วิธีวัดที่เปลี่ยนจากรอบ 15 ตุลาคม: โหมด `--benchmark` รอให้ capture นิ่ง แล้ว **กรองจริง** (คำค้น 5 แบบ + domain/All ซ้ำ 5 รอบ = 37 ตัวอย่าง end-to-end) และ **เลือกแถวจริง 25 แถว** กระจายทั่วรายการ harness จะ fail หาก `benchmarkComplete` ไม่เป็นจริง, ตัวอย่างน้อยกว่า 20, หรือมี timeout

- **Selection-to-render**: เปลี่ยน `selectedID` จนถึง text layout (`ensureLayout`) เสร็จในทุก pane ที่แสดง (Request + Response) แยกเป็น select→detail พร้อม (fetch + format ใน detached task + เข้าคิว main actor) และ detail พร้อม→layout เสร็จ
- **Filter end-to-end**: การกรองของผู้ใช้ (หลัง debounce 150 ms) จนถึง `NSTableView.reloadData` + sort เสร็จ ไม่รวมการวาด cell; `filterModelOnly` คือเฉพาะ filter + สรุป sidebar
- ทั้งสองค่าไม่ใช่ scroll/frame hitch (ต้องใช้ Instruments)

| ชุดทดสอบ | ปริมาณ / ผลรวม | UI RSS · CPU* | Engine RSS · CPU* | Storage (preview) | RSS รวม peak |
|---|---|---|---|---|---|
| Engine HTTPS burst (engine อย่างเดียว) | 10,000 req, 113.6 วินาที ≈ 88.0 req/s | n/a | — | 105.1 MiB (10,000 files) | 329 MB |
| Native HTTP burst | 10,000 req, 44.4 วินาที ≈ 225 req/s | 197 MB · 38.4% | 186 MB · 2.8% | 105.1 MiB (10,000 files) | 381 MB |
| Native HTTP paced | 300 req @ 10 req/s, 29.9 วินาที ≈ 10.03 req/s | 168 MB · 40.7% | 109 MB · 0.8% | 3.2 MiB (304 files) | 275 MB |

\* ค่า ณ ตัวอย่างสุดท้ายหลัง benchmark; CPU เป็น decaying average ของ `ps` จึงรวมช่วงกรอง/เลือกแถวและไม่ใช่ interval CPU ห้ามใช้ตั้งเพดาน CPU RSS ของ tree อาจนับ shared pages ซ้ำ

| Latency (ms) | Native burst 10,004 rows | Native paced 304 rows | เป้าตั้งต้น |
|---|---|---|---|
| Filter end-to-end p50 / p95 | 56.1 / **89.7** | 43.6 / 69.3 | p95 ≤ 100 ที่ 10,000 rows |
| Filter model only p50 / p95 | 11.0 / 31.4 | 0.5 / 1.4 | — |
| Selection → render p50 / p95 | 242.0 / **251.6** | 223.1 / **254.0** | p95 ≤ 250 (preview ≤ 256 KiB) |
| ↳ select → detail พร้อม p50 / p95 | 30.1 / 56.0 | 31.0 / 53.7 | — |
| ↳ detail พร้อม → layout เสร็จ p50 / p95 | 212.6 / 221.9 | 192.7 / 223.9 | — |

ข้อค้นพบสำคัญ:

- Filter p95 ผ่านเป้า 100 ms แต่เหลือ margin แค่ ~10 ms ที่ 10,000 rows (ส่วนที่โตตามจำนวนแถวคือการสรุป sidebar ใน `rebuildRows`, p95 31 ms ต่อ model-only)
- **Selection-to-render p95 อยู่ที่ 251–254 ms จึง "ไม่ผ่าน" เป้า 250 ms แบบหวุดหวิด** และต้นทุนส่วนใหญ่ (~190–220 ms) คือ text layout ของ inspector ไม่ใช่ fetch/format ที่ ~30 ms รอบ 15 ตุลาคมเคยได้ detail fetch ≈ 0 ms เพราะไม่ได้เลือกแถว ห้ามนำค่านั้นมาเทียบ ยังไม่ปรับ performance ใน P0; ต้องตัดสินใจว่าจะแก้ layout ใน P3 หรือปรับเป้า
- Preview disk ที่ 10,000 flows ใช้ ~105 MiB ภายใต้งบ 128 MiB (เหลือ ~18%)
- Payload ทดสอบเป็น JSON 10 KB ที่มี string ยาวบรรทัดเดียว ยังไม่ใช่ตัวแทนของ body หลายขนาด/encoding

### Resource & latency budgets (ใช้เป็นเกณฑ์ regression จนกว่าจะมีผลจากเครื่องทีม)

| รายการ | งบ | ที่มา |
|---|---|---|
| Filter end-to-end p95 @ 10,000 rows | ≤ 100 ms | เป้าตั้งต้นใน PLAN; วัดได้ 89.7 |
| Selection-to-render p95 (preview ≤ 256 KiB) | ≤ 250 ms (**ยังไม่ผ่าน** วัดได้ 251.6–254.0) | เป้าตั้งต้นใน PLAN |
| UI RSS @ 10,000 rows | ≤ 250 MB (วัดได้ 197 MB) | baseline + ~25% |
| Engine RSS @ 10,000 retained | ≤ 250 MB (วัดได้ 186 MB; engine-only burst 329 MB รวม HTTPS fixture) | baseline + ~25% |
| Preview disk | ≤ 128 MiB (วัดได้ 105 MiB) | ขีดจำกัดของ engine |
| CPU | ยังไม่กำหนดเพดาน | `ps` decaying average ไม่ใช่ interval CPU |

งบ RAM เป็นเพดานสำหรับเครื่อง 16 GB เท่านั้น ยังต้องยืนยันบนเครื่อง RAM 8 GB และ macOS 14

Raw reports: [engine HTTPS](benchmarks/engine-https-burst.json), [native burst](benchmarks/native-burst-baseline.json), [native paced](benchmarks/native-paced-baseline.json); รอบเดิมเก็บไว้ที่ `benchmarks/2026-10-15/`

### P0 contract/regression tests

Swift suite 87 tests ผ่าน (เพิ่ม 9): legacy `FlowDetail`/`TrafficFlow` ที่ไม่มี `number`/`client`/`captureState`, `rules.json` เก่าที่ไม่มี `bodySource`, API version (`nil` = legacy, 0/2/3/99/-1 ถูกปฏิเสธ), body completeness ทั้ง 5 สถานะ + `nil` กับ Map Local prefill/inspector, การแยก UI/engine process tree, percentile และ lifecycle ของ selection-render/filter samples Engine smoke, rules smoke และ native GUI smoke (100 requests) ผ่านด้วย isolated ports/data

ยังต้องวัด: scroll/frame hitches (Instruments), cold start, idle CPU, 10,000 requests @ 10 req/s ต่อเนื่อง (~17 นาที), body ขนาดใหญ่/หลาย encoding, HTTP/2, WS/SSE soak, engine crash/recovery, อุปกรณ์จริง และ macOS 14 / RAM 8 GB

---

# Baseline — 15 ตุลาคม 2026 (ประวัติ)

ผลเบื้องต้นจาก release build บน Apple Silicon / RAM 16 GB / macOS 27.0.1 ยังไม่ใช่เกณฑ์ตรวจรับ และยังไม่ได้ยืนยันบน macOS 14 หรือเครื่อง RAM 8 GB

| ชุดทดสอบ | ปริมาณและ payload | ผล | RAM รวม UI + engine |
|---|---|---|---|
| Native HTTP burst | 10,000 requests, body 10,224 bytes/request | 67.69 วินาที ≈ 147.73 requests/s; UI เก็บ 10,000 แถวล่าสุด | ช่วงท้าย UI snapshot 332 MB; sampler peak ≈331 MB |
| Native HTTP paced | 300 requests, body 10,224 bytes/request, จำกัด 10 requests/s | 29.91 วินาที ≈10.03 requests/s | ช่วงท้าย UI snapshot 255 MB; sampler peak ≈253 MB |

สอง sampler ใช้คนละเวลา จึงได้ค่าช่วงท้ายและ peak ต่างกันเล็กน้อย RSS เป็นผลรวมทั้ง process tree และอาจนับ shared pages ซ้ำ ไม่ใช่ physical footprint ตาม Instruments

- Burst run วัดก่อนเพิ่มการข้าม table reload เมื่อข้อมูลไม่เปลี่ยนและ disk preview budget; paced run ใช้สองการปรับนี้แล้ว การเปลี่ยนแปลงภายหลังเป็น proxy recovery tests/ข้อความ UI ไม่ได้เปลี่ยนเส้นทาง capture
- Burst run: filter ครั้งล่าสุดประมาณ 0.54ms เป็นกรณี search ว่าง ไม่ใช่ผลค้นหาเต็มรูปแบบ ส่วน unit benchmark สำหรับค้นหา `active` ใน 10,000 แถวใช้เวลาประมาณ 17ms บน debug build
- Detail fetch ใน automated GUI reports เป็น 0 เพราะ harness ไม่ได้เลือกแถว ไม่ควรนำไปตีความเป็นความเร็วโหลด body
- ได้ตรวจผ่านหน้าจอจริงแยกต่างหาก: Start → HTTPS/HTTP2 request → เลือกแถว → สลับ Request/Response headers/body → Stop โดยใช้ curl ที่ระบุ CA เฉพาะคำสั่ง ไม่เปลี่ยน system proxy/Keychain
- ค่า CPU ใน JSON เป็นค่าที่ macOS `ps` รายงาน: decaying average ย้อนหลังได้ถึงประมาณหนึ่งนาที ตาม `man ps` ไม่ใช่ค่าเฉลี่ยตลอดอายุ process และไม่ใช่การวัดเป็นช่วงเวลาคงที่ จึงยังไม่กำหนดเพดาน CPU จากข้อมูลนี้
- ชุด native paced กับ engine HTTPS stress ถูกเรียกพร้อมกัน จึงมีการแข่งขัน CPU/I/O; ต้องรันแยกบนเครื่องทีมเพื่อได้ baseline สำหรับตัดสิน performance budget

Engine HTTPS stress แยกต่างหาก: 10,000 requests ใช้ 110.99 วินาที (~90.10 requests/s), peak RSS engine tree ~359 MB และ preview disk ~104 MiB; เก็บ metadata/detail ล่าสุดครบ 10,000 รายการ ภายใต้งบ preview 128 MiB ผลนี้ใช้ HTTPS หลาย connections ต่างจาก HTTP GUI test จึงไม่ควรเทียบ RAM โดยตรง

Raw reports: [burst](benchmarks/2026-10-15/native-burst-baseline.json), [paced](benchmarks/2026-10-15/native-paced-baseline.json), [engine HTTPS](benchmarks/2026-10-15/engine-https-burst.json)

Integration รอบสุดท้ายผ่าน HTTPS, streaming, encoded-body handling, API authentication และ WebSocket echo 20 messages หลังจำกัด message history โดยไม่ได้แก้ system proxy/Keychain

สิ่งที่ยังต้องวัด: scroll/frame hitches ใน Instruments, cold start, idle CPU หลังรันนิ่ง, 10,000 requests ที่ 10 requests/s แบบต่อเนื่อง (~17 นาที), body ขนาดใหญ่, engine crash/recovery, อุปกรณ์จริง และ macOS 14

## Workspace/API contract smoke — 26 ตุลาคม 2026

- ก่อนปรับ workspace: Swift tests เดิมผ่าน 38 tests; หลังเพิ่ม API/body-state compatibility และ native split-view tests ผ่าน 43 tests
- Release app build และตรวจ bundle signature ผ่าน เป็น development/ad-hoc signature ตามเดิม
- Engine smoke แยก: HTTPS 100 requests พร้อม fixture อีก 4 flows ผ่าน API v1, complete/streamed/encoded capture states, token/origin rejection และ WebSocket echo 20 messages
- Native app smoke แยก: HTTP 100 requests พร้อม fixture อีก 4 flows; UI รายงานครบ 104 flows/104 rows, process-tree sampler peak ประมาณ 255 MB บน RAM 16 GB/macOS 27.0.1
- Rules smoke ผ่าน Map Local, breakpoint edits, streaming/encoded preservation, 32-paused limit, cancellation และ persisted rules หลัง restart
- Native window tests ตรวจ minimum pane sizes, เก็บ hosting controllers เดิมเมื่อสลับ orientation และ restore divider เมื่อสร้าง workspace ใหม่
- Harness รอ metrics snapshot ให้ถึง expected flow count ภายในเพดาน แทนสมมติว่า snapshot รอบทุก 2 วินาทีจะทันเสมอ; หากไม่ทันหรือจำนวนผิดจะ fail พร้อม diagnostics
- รอบนี้เป็น smoke ไม่ใช่ performance acceptance: ไม่เทียบ throughput กับชุด 10,000 requests เดิม, ยังไม่ได้วัด selection-to-render/p95/frame hitches, light/dark/VoiceOver แบบ interactive หรือยืนยันบน macOS 14; GUI harness ยังไม่ได้เลือกแถว จึงห้ามตีความ detail time ที่เป็นศูนย์ว่าโหลดทันที
- ทดสอบด้วย isolated test data/CA ไม่แก้ system proxy หรือ Keychain; reports รอบนี้อยู่ใน cache ของเครื่องและไม่ได้เพิ่มแทน raw baseline เดิม
