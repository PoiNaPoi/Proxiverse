# คู่มือใช้งาน Reqnivo ภาษาไทย

[กลับไปหน้า README](../README.md)

คู่มือนี้เริ่มตั้งแต่เปิดแอปครั้งแรกไปจนถึงอ่าน API, จำลอง response และหยุด request เพื่อแก้ไขก่อนส่งต่อ ชื่อปุ่มภาษาอังกฤษในคู่มือตรงกับหน้าจอแอป เพื่อให้เปิดอ่านแล้วทำตามได้ทีละขั้น

Reqnivo เป็นแอปบน Mac สำหรับตรวจ HTTP/HTTPS ที่ส่งผ่าน proxy ของแอป ใช้ได้ทั้งกับโปรแกรมบน Mac, โทรศัพท์, iOS Simulator และ Android Emulator โดยมี capture engine รวมมาให้แล้ว ผู้ใช้แอปไม่ต้องติดตั้ง Python

รุ่นปัจจุบันเป็น early beta รองรับ Apple Silicon และตั้งเป้าหมาย macOS 14 ขึ้นไป ไม่มี build สำหรับ Intel การตั้ง deployment target ไม่ได้ยืนยันว่าทดสอบครบทุกเวอร์ชัน macOS โปรดอ่านผลทดสอบและข้อจำกัดของไฟล์ที่ดาวน์โหลดใน release notes ด้วย

## สารบัญ

1. [คำศัพท์และหลักการทำงาน](#basics)
2. [ดาวน์โหลดและเปิดแอปครั้งแรก](#installation)
3. [รู้จักหน้าจอและปุ่มต่าง ๆ](#workspace)
4. [เริ่มจับ traffic จาก Mac](#mac-capture)
5. [เปิดอ่าน HTTPS และติดตั้ง CA บน Mac](#https)
6. [เชื่อมต่อ iPhone และ iPad](#ios-device)
7. [เชื่อมต่อ Android เครื่องจริง](#android-device)
8. [เชื่อมต่อ iOS Simulator และ Android Emulator](#simulators)
9. [อ่าน Request, Response และ JSON](#inspector)
10. [ค้นหา กรอง บันทึกตัวกรอง และปักหมุด](#filters)
11. [Map Local: จำลองผลลัพธ์ API](#map-local)
12. [นำเข้าและส่งออกกฎ Map Local](#rule-transfer)
13. [Breakpoint: หยุดและแก้ request/response](#breakpoints)
14. [Capture Settings และ CA ของเซิร์ฟเวอร์](#settings)
15. [แก้ปัญหาที่พบบ่อย](#troubleshooting)
16. [จบการทดสอบและคืนค่าเครือข่าย](#cleanup)
17. [ข้อมูลที่บันทึกและข้อจำกัด](#storage)
18. [แบบฝึกหัดตั้งแต่ต้นจนจบ](#walkthrough)
19. [ภาคผนวกสำหรับนักพัฒนา](#development)

<a id="basics"></a>

## 1. คำศัพท์และหลักการทำงาน

| คำที่พบ | ความหมายและตัวอย่าง |
| --- | --- |
| Client | โปรแกรมที่เรียก API เช่น Safari หรือแอปที่กำลังทดสอบบนมือถือ |
| Server | เครื่องปลายทางที่ให้บริการ API |
| Proxy | จุดที่ client ส่งข้อมูลผ่านก่อนถึง server ในที่นี้คือ Reqnivo บน Mac |
| Traffic | คำขอและคำตอบที่วิ่งผ่าน proxy |
| Request | ข้อมูลที่ client ส่ง เช่น `GET /products` หรือข้อมูล JSON ตอนกดบันทึก |
| Response | ข้อมูลที่ server ตอบ เช่น status `200` และรายการสินค้า |
| Host / Domain | ชื่อปลายทาง เช่น `api.example.com` ไม่รวม `https://` และ path |
| Path + query | ส่วนหลังชื่อ host เช่น `/products?page=1` |
| Method | ประเภทคำขอ เช่น `GET` อ่านข้อมูล, `POST` ส่งข้อมูล แต่พฤติกรรมจริงขึ้นกับ API |
| Headers | ข้อมูลประกอบ เช่น `Content-Type`, `Authorization` และ `Cookie` |
| Body | เนื้อหาคำขอหรือคำตอบ เช่น JSON; บางรายการไม่มี body เป็นปกติ |
| Status | รหัสคำตอบ เช่น `200` สำเร็จ, `401` ต้องตรวจการยืนยันตัวตน, `500` ข้อผิดพลาดฝั่ง server |
| CA certificate | ใบรับรองที่ติดตั้งและเชื่อถือบน client เพื่อให้ proxy ถอดรหัส HTTPS ได้ |
| Decryption | การเปิดอ่าน HTTPS เฉพาะโดเมนที่เลือก |
| Map Local | ตอบ API ด้วยไฟล์หรือข้อความที่เรากำหนดแทน response จาก server |
| Breakpoint | หยุด request หรือ response ไว้ เพื่ออ่านและแก้ก่อนกดส่งต่อ |
| Inspector | แผงรายละเอียดของรายการที่เลือก แสดง Request และ Response |

เมื่อใช้งานปกติ ข้อมูลเดินทางจาก client ผ่าน Reqnivo ไปยัง server และคำตอบย้อนกลับผ่าน Reqnivo มายัง client การเปิดแอปอย่างเดียวไม่ได้ทำให้ทุกโปรแกรมส่งข้อมูลผ่าน proxy ต้องตั้งค่าที่ client หรือเปิด **Capture Mac Traffic** ก่อน

การอ่าน HTTPS ต้องครบสามอย่าง: client ส่งผ่าน proxy, client เชื่อถือ CA ของ Mac เครื่องที่จับ traffic และเปิด decryption ให้ hostname นั้น ถ้าขาดอย่างใดอย่างหนึ่งอาจเห็นเพียง connection ที่เข้ารหัส หรือ client เชื่อมต่อไม่สำเร็จ

ใช้กับระบบและอุปกรณ์ที่ได้รับอนุญาตให้ทดสอบ ข้อมูลที่เห็นอาจมี token, cookie และข้อมูลส่วนบุคคล แอปไม่ได้ปิดบังข้อมูลเหล่านี้อัตโนมัติ อ่าน [ขอบเขตการใช้งาน](AUTHORIZED_USE.md) และ [ข้อมูลส่วนบุคคลและการลบข้อมูล](PRIVACY.md) ก่อนใช้ข้อมูลจริง

<a id="installation"></a>

## 2. ดาวน์โหลดและเปิดแอปครั้งแรก

### 2.1 ติดตั้งจากไฟล์ ZIP

1. ดาวน์โหลดไฟล์ macOS arm64 ZIP จาก [GitHub Releases ของ Reqnivo](https://github.com/PoiNaPoi/Reqnivo/releases)
2. แตก ZIP แล้วลาก **Reqnivo.app** ไปไว้ใน **Applications**
3. เปิดแอปจาก Applications
4. build ปัจจุบันใช้ ad-hoc signature และยังไม่ผ่าน Apple notarization ถ้า macOS บล็อก ให้ตรวจสอบแหล่งดาวน์โหลด แล้วใช้ตัวเลือกอนุญาตใน **System Settings → Privacy & Security** ตามที่ macOS แสดง
5. เมื่อเปิดแอป แอปจะพยายามเริ่ม capture อัตโนมัติหนึ่งครั้งในการเปิดรอบนั้น ถ้าเริ่มไม่สำเร็จ ให้อ่านข้อความผิดพลาด แก้การตั้งค่า แล้วกด **Start Capture**

สำหรับค่าตั้งต้นใหม่ proxy รับที่ `127.0.0.1:9090` และ control API ใช้ `127.0.0.1:9091` ยังไม่เปิดให้มือถือในเครือข่ายเข้ามา และยังไม่เปิด decryption ของ HTTPS โดเมนใด หากเคยใช้แอปแล้ว ค่าที่บันทึกไว้จะถูกโหลดกลับ

หากมี source code และต้องการ build เอง ดู [ภาคผนวกนักพัฒนา](#development) ผู้ใช้ ZIP ข้ามส่วนนั้นได้เลย

### 2.2 รู้จัก IP และ port ก่อนตั้งค่ามือถือ

| เครื่องที่ใช้งาน | Proxy server ที่ใช้ | Port ตัวอย่าง |
| --- | --- | --- |
| โปรแกรมบน Mac เครื่องเดียวกัน | `127.0.0.1` | `9090` |
| iPhone/iPad/Android เครื่องจริง | LAN IP ของ Mac เช่น `192.168.1.25` | `9090` |
| Android Emulator มาตรฐาน | `10.0.2.2` | `9090` |
| Control API ภายในแอป | ไม่ต้องนำไปใส่ในมือถือ | `9091` |

IP `192.168.1.25` ในคู่มือเป็นตัวอย่าง ต้องแทนด้วย IP ที่แอปแสดงจริง ส่วน `0.0.0.0` หมายถึง listener รับบนทุก IPv4 interface ไม่ใช่ที่อยู่สำหรับกรอกบนโทรศัพท์

หากหน้าตั้งค่ามือถือแยกช่อง Server และ Port ให้กรอก IP อย่างเดียวใน Server และกรอกเลข port อีกช่อง ไม่ใส่ `http://` หรือรวม `:9090` ในช่อง Server และอย่าใช้ `127.0.0.1` บนมือถือ เพราะจะหมายถึงตัวมือถือเอง

<a id="workspace"></a>

## 3. รู้จักหน้าจอและปุ่มต่าง ๆ

### 3.1 แถบเครื่องมือด้านบน

| ปุ่ม | ใช้ทำอะไร |
| --- | --- |
| **Start Capture / Stop** | เริ่มหรือหยุด engine; Stop ยกเลิกรายการที่ค้างที่ breakpoint และพยายามคืนค่า Mac proxy ที่แอปเปลี่ยน |
| **Clear** | ล้างรายการที่แสดงและ selection/pin ของ request; ไม่ใช่คำสั่งลบข้อมูลทั้งหมดบนดิสก์ |
| **Map Local** | เปิดหน้าต่างจัดการกฎ response จำลอง |
| **Breakpoints** | เปิดกฎหยุด request/response; ตัวเลขบนปุ่มบอกจำนวนรายการที่กำลังหยุดรอ |
| **HTTPS** | จัดการโดเมนที่บันทึกไว้สำหรับ decryption |
| **Settings** | เปิด **Capture Settings** เช่น port, LAN และ network service |
| **Certificate** | เปิด **Install Certificate** สำหรับดู public CA และติดตั้งบนอุปกรณ์ |
| **Layout** | จัดตำแหน่ง Inspector และ Request/Response รวมถึง reset คอลัมน์ |

### 3.2 Sidebar ด้านซ้าย

- **All Traffic**: ดูทุกรายการที่ยังเก็บอยู่ ถ้าหา request ไม่เจอให้กลับมาที่นี่ก่อน
- **Domains**: เลือก host เพื่อดูเฉพาะโดเมนนั้น กางรายการเพื่อเลือก path ที่พบได้ คลิกขวาเพื่อเปิด/ปิด decryption หรือ **Pin / Unpin** โดเมน
- **Clients**: เลือกดูตาม IP ต้นทาง เช่น แยก traffic จาก Mac และโทรศัพท์ ค่า `Unknown` หมายถึงข้อมูลนั้นไม่มี client attribution
- ส่วนล่างแสดงสถานะ capture, LAN, Mac proxy และ CA ของ Mac แต่ละสถานะตรวจคนละเรื่อง Capture ทำงานไม่ได้แปลว่า client ตั้ง proxy และ trust CA ครบแล้ว
- เมื่อเปิด LAN จะมี **Proxy IP : Port** พร้อมปุ่มคัดลอก เลือก IP ที่โทรศัพท์เข้าถึงได้ ถ้าเปลี่ยน Wi-Fi ให้ตรวจ IP ใหม่
- **Capture Mac Traffic**: เปิดให้โปรแกรมที่ใช้ system proxy ของ network service ที่เลือกส่งผ่านแอป

### 3.3 ตาราง traffic และแผงรายละเอียด

คลิกแถวในตารางเพื่อเปิด Inspector ดู Request/Response กดหัวคอลัมน์เพื่อเรียง และกดอีกครั้งเพื่อกลับทิศทาง คอลัมน์ที่เรียงได้มี ID, Method, Status, Source, Host, Path, Time และ Size ค่าที่ไม่ทราบหรือยังรออยู่จะอยู่ท้ายตาราง

ID เป็นเลขรายการในรอบ capture ไม่เปลี่ยนตาม filter หรือ sort ชี้ที่ ID เพื่อดู flow UUID ค่าเริ่มต้นเรียง ID มากไปน้อย ให้รายการใหม่อยู่บนสุด

**Show Inspector / Hide Inspector** ใช้แสดงหรือซ่อนรายละเอียด ต้องเลือก request ก่อน ส่วนจำนวน `N of M retained` หมายถึงแสดง N รายการจาก M รายการที่ยังเก็บอยู่ จำนวน captured ด้านล่างอาจมากกว่า เพราะข้อมูลเก่าถูกนำออกตามขีดจำกัดแล้ว

ใน **Layout** เปิด **Inspector on Right** เพื่อย้ายรายละเอียดไปขวา ปิดเพื่อวางด้านล่าง และใช้ **Stack Request and Response** เพื่อวาง Request/Response บนล่าง สามารถลาก divider ปรับพื้นที่ได้

<a id="mac-capture"></a>

## 4. เริ่มจับ traffic จาก Mac

### 4.1 จับจาก Safari หรือแอปที่ใช้ system proxy

1. เปิด Reqnivo แล้วตรวจว่า capture กำลังทำงาน หากหยุดอยู่ให้กด **Start Capture**
2. ติ๊ก **Capture Mac Traffic** ด้านล่าง sidebar
3. อนุมัติคำขอสิทธิ์ของ macOS เพื่อเปลี่ยน proxy รูปแบบการยืนยันตัวตนขึ้นกับเครื่องและบัญชี อาจเป็นรหัสผ่านหรือ Touch ID
4. เปิด Safari แล้วเรียกเว็บหรือระบบทดสอบที่ได้รับอนุญาต
5. กลับมาที่ **All Traffic** และล้างข้อความค้นหาหากมี
6. ควรมีรายการจากโปรแกรมนั้นเข้ามา หากเป็น HTTPS ที่ยังไม่ได้เปิด decryption อาจเห็น `CONNECT` และ **Encrypted** ซึ่งแปลว่า traffic ผ่าน proxy แล้ว แต่ยังอ่าน API ภายในไม่ได้
7. ทำ [ขั้นตอน HTTPS](#https) เพื่อเปิดอ่าน headers/body

ถ้าต้องเลือก Wi-Fi หรือ Ethernet ให้ **Stop → Settings → Mac network service** เลือก service ที่ใช้งาน แล้ว Start ใหม่ ตัวเลือก service เปิดให้แก้เมื่อเปิด Capture Mac Traffic

เปิด/ปิด **Capture Mac Traffic** ระหว่าง capture ได้ทันทีโดยไม่ต้องล้าง log หากเปลี่ยนตอนหยุดอยู่ จะใช้ค่าตอน Start ครั้งถัดไป การทำงานนี้ครอบคลุมโปรแกรมที่ใช้ system proxy เท่านั้น บางโปรแกรมมีการตั้ง proxy ของตัวเอง

### 4.2 ทดสอบผ่าน Terminal โดยไม่เปลี่ยน system proxy

เมื่อ capture ทำงานที่ port 9090 สามารถส่ง HTTP ผ่าน proxy เฉพาะคำสั่งนี้:

```sh
curl --noproxy '' --proxy http://127.0.0.1:9090 http://example.com/
```

ควรเห็นแถว host `example.com` ในตาราง ถึง server จะ redirect ก็ยังใช้ตรวจว่า request ผ่าน proxy ได้ `--noproxy ''` ป้องกันรายการ bypass ของ curl ทำให้ข้าม proxy

ถ้าเปลี่ยน Proxy port ให้แก้เลขในคำสั่งด้วย วิธีนี้ไม่ต้องเปิด Capture Mac Traffic และไม่ต้องติดตั้ง CA เพราะตัวอย่างใช้ HTTP

<a id="https"></a>

## 5. เปิดอ่าน HTTPS และติดตั้ง CA บน Mac

### 5.1 ติดตั้งและเชื่อถือ CA บน Mac

1. เริ่ม capture อย่างน้อยหนึ่งครั้ง เพื่อให้ engine สร้าง CA ของ Mac เครื่องนี้
2. กด **Certificate → Show Public CA Certificate** หรือ **Settings → Show Public CA Certificate**
3. ใช้ไฟล์ public CA ที่แอปเปิดให้ คือ `mitmproxy-ca-cert.pem` ภายใต้ `~/Library/Application Support/Reqnivo/ca/` สำหรับค่า data directory ปกติ
4. เปิดไฟล์ด้วย **Keychain Access** แล้วเพิ่มลง keychain ที่ใช้กับการทดสอบ หากแอปเปิดให้เห็นไฟล์ใน Finder ให้เปิดไฟล์จากตรงนั้น
5. ใน Keychain Access หา certificate ของ mitmproxy ให้ตรงกับไฟล์จาก Mac เครื่องนี้ ดับเบิลคลิกเพื่อเปิดรายละเอียด
6. กาง **Trust** แล้วตั้ง **When using this certificate → Always Trust** ปิดหน้าต่างและยืนยันสิทธิ์เมื่อ macOS ขอ
7. กลับมาที่ Reqnivo รอสถานะตรวจ trust ซึ่งอัปเดตประมาณทุก 2 วินาที เมื่อสำเร็จจะแสดง **HTTPS trusted on this Mac**

ชื่อเมนูอาจต่างตามภาษาและ macOS หากพบ certificate ชื่อซ้ำ ให้ตรวจรายละเอียดว่าเป็น CA ของ capture นี้ ไม่เลือกจากชื่ออย่างเดียว ขั้นตอนเปลี่ยน trust อ้างอิง [Keychain Access ของ Apple](https://support.apple.com/guide/keychain-access/change-the-trust-settings-of-a-certificate-kyca11871/mac)

สถานะ trusted ใน sidebar ตรวจเฉพาะ Mac ไม่ยืนยัน trust บนมือถือ, Simulator หรือโปรแกรมที่มี trust store ของตนเอง เช่น runtime หรือ browser บางตัว

### 5.2 เปิดถอดรหัสโดเมนที่ต้องการ

1. จาก client เรียก URL ทดสอบสักครั้ง เช่น `https://example.com/` ให้ host ปรากฏใน Reqnivo
2. เลือกแถว **Encrypted** แล้วกด **Enable Decryption** หรือคลิกขวาที่โดเมนใน sidebar → **Enable HTTPS Decryption**
3. กด **HTTPS** บน toolbar เพื่อตรวจว่ารายการโดเมนนั้นเปิดอยู่ หน้านี้จัดการโดเมนที่เคยเปิดจากหน้าหลัก ไม่ได้เพิ่มทุกโดเมนที่พบอัตโนมัติ
4. ปิด connection เดิมของ client แล้วเรียกใหม่ วิธีที่ตรงไปตรงมาคือปิดแล้วเปิดโปรแกรมที่ทดสอบใหม่ การ reload อย่างเดียวอาจยังใช้ TLS connection เดิม
5. เลือก request ใหม่ ควรเห็น method/path/status และ headers/body ตามเนื้อหาที่ capture รองรับ

รายการเดิมที่เป็น Encrypted จะไม่ถูกถอดรหัสย้อนหลัง ชื่อโดเมนจับคู่ตรงตัวทุก port เช่นเปิด `api.example.com` จะไม่รวม `sub.api.example.com` ไม่ใช้ wildcard, URL หรือ path ในรายการ HTTPS

เอาติ๊กออกใน **HTTPS** เพื่อปิด decryption แต่เก็บชื่อไว้ หรือกดถังขยะเพื่อลบรายการ การเปลี่ยนมีผลกับ TLS connection ใหม่และจำไว้เมื่อเปิดแอปครั้งถัดไป HTTP จับได้ตามปกติ ส่วน Map Local/Breakpoint ของ HTTPS ต้องเปิด decryption ก่อนจึงจะทำงานกับ API ภายในได้

### 5.3 ตรวจด้วย curl แบบใช้ public CA เฉพาะคำสั่ง

หลังเปิด decryption ให้ `example.com` จากหน้าหลักแล้ว:

```sh
curl --noproxy '' --proxy http://127.0.0.1:9090 \
  --cacert "$HOME/Library/Application Support/Reqnivo/ca/mitmproxy-ca-cert.pem" \
  https://example.com/
```

`--cacert` ให้ curl เชื่อถือ public CA ของ capture นี้โดยไม่ต้องเปลี่ยน Keychain คำสั่งนี้ไม่ใช่การติดตั้ง CA ให้โปรแกรมอื่น ถ้าใช้ data directory หรือ port อื่นให้ปรับตามจริง หลักการติดตั้ง CA อ้างอิง [mitmproxy certificates](https://docs.mitmproxy.org/stable/concepts/certificates/)

<a id="ios-device"></a>

## 6. เชื่อมต่อ iPhone และ iPad

### 6.1 เปิดให้โทรศัพท์เชื่อมต่อ Mac

1. ให้ Mac และโทรศัพท์อยู่เครือข่ายเดียวกันที่เข้าถึงกันได้
2. ใน Reqnivo กด **Stop → Settings**
3. เปิด **Allow test devices on local network** แล้วกด **Done → Start Capture**
4. ดู **Proxy IP : Port** ใน sidebar หรือ **Certificate → Phone / Tablet** จด LAN IP ของ Mac และ Proxy port
5. บน iPhone/iPad เปิด **Settings → Wi-Fi → ปุ่มข้อมูลข้างเครือข่ายที่ใช้งาน → Configure Proxy**
6. เลือก **Manual** แล้วกรอก Server เป็น LAN IP ของ Mac เช่น `192.168.1.25` และ Port เป็น `9090` ตามค่าจริง แล้วบันทึก
7. เปิด Safari บนโทรศัพท์ไปที่ `http://mitm.it` โดยใช้ `http://` หรือสแกน QR ในหน้าต่าง Certificate หลังตั้ง proxy แล้ว

**ตรวจผล:** ต้องเห็นหน้าดาวน์โหลด certificate ของ mitmproxy และควรมี traffic จากโทรศัพท์เข้ามาใน Reqnivo ถ้าไม่เห็นหน้าติดตั้งให้ตรวจ routing/proxy ก่อน ไม่ต้องรีบติดตั้ง CA ใหม่

### 6.2 ติดตั้ง profile และเปิด full trust

1. ใน `http://mitm.it` เลือก platform ของ iPhone/iPad แล้วอนุญาตดาวน์โหลด profile
2. เปิด **Settings → General → VPN & Device Management** เลือก profile ที่ดาวน์โหลด แล้วกดติดตั้ง ยืนยันตามที่อุปกรณ์ขอ
3. เปิด **Settings → General → About → Certificate Trust Settings**
4. เปิด full trust ให้ root certificate ของ mitmproxy ที่เพิ่งติดตั้ง
5. บน Reqnivo เปิด decryption ให้โดเมนที่แอปเรียกตาม [ขั้นตอน HTTPS](#https)
6. ปิดและเปิดแอปที่ทดสอบบนโทรศัพท์ใหม่ แล้วทำรายการที่ต้องการตรวจ

**ตรวจผล:** ต้องเห็น request ใหม่ของโดเมนนั้นที่อ่าน headers/body ได้ การติดตั้ง profile อย่างเดียวยังไม่เปิด SSL/TLS trust ขั้นตอน full trust อ้างอิง [Apple Support](https://support.apple.com/en-us/102390)

ถ้า Safari ใช้ได้แต่แอปทดสอบใช้ไม่ได้ อาจมี trust store หรือ certificate pinning ของแอป ต้องใช้ debug configuration ของแอปทีมที่อนุญาตให้ตรวจ HTTPS

เมื่อเลิกทดสอบ ให้คืนค่า **Configure Proxy** เป็นค่าเดิม เช่น Off และลบ profile/CA ที่ติดตั้งเมื่อไม่ใช้แล้ว ถ้าปิด Reqnivo แต่โทรศัพท์ยังชี้ proxy มาที่ Mac อาจใช้อินเทอร์เน็ตไม่ได้

<a id="android-device"></a>

## 7. เชื่อมต่อ Android เครื่องจริง

### 7.1 ตั้ง Wi-Fi proxy และติดตั้ง CA ด้วยตนเอง

1. เปิด LAN capture บน Mac และดู IP/port เช่นเดียวกับ [ขั้นตอนเชื่อมต่อโทรศัพท์](#ios-device)
2. บน Android เปิดรายละเอียดเครือข่าย Wi-Fi ที่ใช้งาน หา **Proxy → Manual** บางรุ่นอยู่ใน Advanced options หรือเมนูแก้ไขเครือข่าย
3. กรอก Proxy hostname เป็น LAN IP ของ Mac และ Proxy port ตามแอป แล้วบันทึก
4. เปิด browser บนโทรศัพท์ไปที่ `http://mitm.it` ดาวน์โหลด CA สำหรับ Android
5. เปิด **Settings → Security → Install a certificate → CA certificate** แล้วเลือกไฟล์ที่ดาวน์โหลด ชื่อและตำแหน่งเมนูต่างกันตามผู้ผลิต/Android version
6. ทำขั้นตอนยืนยันการติดตั้งบนอุปกรณ์ให้เสร็จ
7. เปิด decryption ให้โดเมนบน Reqnivo แล้วปิด/เปิดแอปที่ทดสอบใหม่

**ตรวจผล:** ต้องเห็น request ใหม่ที่อ่านรายละเอียดได้ หาก browser ใช้ได้แต่แอปใช้ไม่ได้ ให้ดูเรื่อง debug trust ด้านล่าง

### 7.2 ใช้ ADB ช่วยคัดลอก CA

วิธีนี้ต้องมี Android SDK Platform-Tools บน Mac และเปิด USB debugging บนอุปกรณ์ การต่อสาย USB ใช้สำหรับติดตั้ง CA ส่วนการส่ง traffic ยังต้องตั้ง proxy แยก

1. ต่อโทรศัพท์กับ Mac และอนุญาต USB debugging บนหน้าจอโทรศัพท์
2. ใน Reqnivo กด **Certificate → Android / Emulator (ADB)**
3. กด **Refresh** แล้วเลือกอุปกรณ์ใน **Target**
4. สำหรับเครื่องทั่วไปที่ไม่มี root กด **Copy CA & Open Settings**
5. แอปคัดลอก public CA ไปที่ `Download/Reqnivo-CA.cer` และเปิด Security Settings ให้เลือกติดตั้ง CA ด้วยตนเอง
6. ทำขั้นตอนติดตั้งบนอุปกรณ์จนจบ ข้อความว่า copied หมายถึงคัดลอกแล้ว ยังไม่ได้ยืนยันว่า Android ติดตั้งหรือ trust สำเร็จ

**Install CA Automatically** ใช้ได้กับ root ADB เช่น debug emulator ที่รองรับเท่านั้น แอปติดตั้งและอ่านกลับมาตรวจใน **user CA store** ไม่ใช่ system CA โทรศัพท์ไม่มี root และ Google Play emulator image ให้ใช้วิธีคัดลอกแล้วติดตั้งเอง

แอปค้นหา ADB จาก `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `~/Library/Android/sdk`, PATH และตำแหน่ง Homebrew หากขึ้น ADB not found ให้ติดตั้ง Platform-Tools แล้วกด Refresh ใหม่

### 7.3 แอป Android ของทีมต้อง trust user CA

แอปที่ target Android 7/API 24 ขึ้นไปโดยทั่วไปไม่ได้เชื่อถือ user CA อัตโนมัติ แม้ติดตั้ง CA บนอุปกรณ์แล้ว หากเป็นแอปของทีม ให้ตรวจ debug Network Security Configuration และ rebuild/reinstall debug app หลังแก้

ตัวอย่างสำหรับนักพัฒนา เมื่อโครงการมี Network Security Configuration อยู่แล้ว ให้รวมส่วน debug trust เข้ากับไฟล์เดิมอย่างเหมาะสม:

```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <debug-overrides>
        <trust-anchors>
            <certificates src="user" />
        </trust-anchors>
    </debug-overrides>
</network-security-config>
```

ไฟล์ XML ต้องถูกอ้างผ่าน `android:networkSecurityConfig="@xml/network_security_config"` ใน `<application>` ของ manifest ด้วย `debug-overrides` มีผลเมื่อ `android:debuggable` เป็น true ให้รักษา configuration เดิมของโครงการ และตรวจ network library/pinning ที่แอปใช้แยกด้วย รายละเอียดอ้างอิง [Android Network Security Configuration](https://developer.android.com/privacy-and-security/security-config)

ติดตั้ง CA แล้วไม่ได้หมายความว่าใช้ได้กับทุกแอป Reqnivo ไม่ได้ปรับ certificate pinning ของแอปภายนอกให้เอง เมื่อทดสอบจบให้คืน proxy เป็นค่าเดิมและลบ user CA ที่ไม่ใช้แล้ว

<a id="simulators"></a>

## 8. เชื่อมต่อ iOS Simulator และ Android Emulator

### 8.1 iOS Simulator

1. เปิด Simulator ที่ต้องการทดสอบจาก Xcode และรอให้ boot เสร็จ
2. เริ่ม capture บน Reqnivo อย่างน้อยหนึ่งครั้งเพื่อสร้าง CA
3. กด **Certificate → iOS Simulator → Refresh**
4. เลือกเครื่องใน **Target** แล้วกด **Install & Trust CA** แอปใช้ `xcrun simctl keychain <UDID> add-root-cert` กับเครื่องที่เลือก
5. ตั้งทางผ่าน proxy แยกจากการติดตั้ง CA โดยเปิด **Capture Mac Traffic** และเลือก Mac network service ให้ตรงกับที่ใช้
6. เปิด Safari ใน Simulator เรียกเว็บทดสอบ แล้วตรวจว่ามีรายการเข้าตาราง
7. เปิด decryption ให้โดเมน ปิด connection เดิม/เปิด client ใหม่ แล้วเรียกอีกครั้ง

**ตรวจผล:** ต้องเห็น request ที่อ่านรายละเอียดได้ การติดตั้ง CA ไม่ต้อง rebuild แอปเพื่อเพิ่ม cert อย่างเดียว แต่แอปที่มี pinning หรือ configuration เฉพาะอาจต้องแก้ debug build ของทีม การใช้ Mac system proxy กับ Simulator ควรตรวจจริงกับเวอร์ชันที่ทีมใช้

ถ้า Refresh แล้วไม่พบเครื่อง ให้เปิด Simulator ให้ boot ก่อน หากมีหลายเครื่องให้ตรวจ Target ทุกครั้งเพื่อไม่ติดตั้งผิดเครื่อง

### 8.2 Android Emulator ของ Android Studio

1. เปิด emulator และรอ boot เสร็จ
2. บน Reqnivo กด **Stop → Settings** เปิด **Allow test devices on local network** แล้ว Start ใหม่
3. ตั้ง proxy ของ emulator เป็น host `10.0.2.2` และ port ของ Reqnivo เช่น `9090` โดยใช้หน้าตั้ง proxy ของ environment ที่ใช้งาน
4. กด **Certificate → Android / Emulator (ADB) → Refresh** แล้วเลือก emulator
5. ถ้าเป็น debug emulator ที่รองรับ root ADB กด **Install CA Automatically** แอปสามารถเรียก `adb root` ให้เอง
6. หาก root ไม่ได้ เช่น Google Play image ใช้ **Copy CA & Open Settings** และติดตั้ง user CA ด้วยตนเอง
7. ตรวจ debug trust ของแอป เปิด decryption ให้โดเมน แล้วเปิดแอปทดสอบใหม่

`10.0.2.2` เป็นที่อยู่พิเศษที่ Android Emulator มาตรฐานใช้เข้าถึง host Mac ต่างจาก LAN IP ที่ใช้กับโทรศัพท์จริง อ้างอิง [Android Emulator networking](https://developer.android.com/studio/run/emulator-networking)

แอปติดตั้ง CA อัตโนมัติเป็น user CA ผ่าน Android TrustedCertificateStore ไม่ต้องติดตั้ง APK เพิ่มหรือ restart emulator แต่ client อาจต้องเปิดใหม่เพื่อเลิกใช้ trust cache เดิม ตัวช่วยใช้ internal Android API จึงอาจไม่รองรับ Android/OEM บางรุ่น หากแอปตรวจยืนยันไม่สำเร็จให้ดู error และใช้วิธีติดตั้งเอง

<a id="inspector"></a>

## 9. อ่าน Request, Response และ JSON

### 9.1 หา API ที่สัมพันธ์กับปุ่มบนแอป

1. ตั้ง proxy และ HTTPS ให้เรียบร้อย
2. กลับ **All Traffic** แล้วกด **Clear** เพื่อเริ่มดูรายการใหม่ให้ง่ายขึ้น
3. บนแอปที่ทดสอบ ทำเพียงหนึ่ง action เช่นเปิดหน้ารายการสินค้า
4. เลือกโดเมน API ใน sidebar หรือค้นหาด้วย host/path
5. เลือกแถวที่ต้องการ แล้วตรวจ Request ก่อนว่าเป็น endpoint และ method ที่คาดไว้
6. ตรวจ Response ว่า status และ body สอดคล้องกับผลบนหน้าจอหรือไม่

### 9.2 อ่านฝั่ง Request

ดู URL/path/query ว่าส่งไปที่ใด ใช้ method อะไร จากนั้นเปิด **Headers** เพื่อตรวจค่าที่ส่ง เช่น `Content-Type` หรือมี Authorization ตามที่ API ต้องการหรือไม่ เปิด **JSON / Body** เพื่อตรวจ payload ที่ผู้ใช้กรอก

ตัวอย่าง `POST /orders` ที่มี `{"quantity":2}` ช่วยแยกได้ว่า client ส่งจำนวนผิดตั้งแต่ต้น หรือ server ประมวลผลแล้วตอบไม่ตรง แผง Request ไม่มี body สำหรับ GET บางรายการเป็นเรื่องปกติ

### 9.3 อ่านฝั่ง Response

ตรวจ status ก่อน แล้วดู headers โดยเฉพาะ Content-Type จากนั้นอ่าน JSON/Body ตัวอย่าง status `200` แต่ body มีรายการว่าง อาจเป็นข้อมูลที่ server ตอบจริง ต้องเทียบสัญญา API และ request ที่ส่ง ไม่ตัดสินจาก status อย่างเดียว

Request และ Response เลือกแท็บแยกกันได้ เช่นดู Request Headers พร้อม Response JSON

### 9.4 JSON folding และการคัดลอก

- JSON จัดรูปแบบและแยกสีอัตโนมัติ กดลูกศรข้างบรรทัด `{` หรือ `[` เพื่อพับ/ขยาย object หรือ array
- การพับเป็นการซ่อนบางส่วนบนหน้าจอ ไม่ได้ลบข้อมูล
- **Copy JSON** คัดลอกข้อความที่มีใน preview ทั้งก้อน แม้บางส่วนพับอยู่ แต่ถ้า preview ถูกตัด จะไม่ทำให้ได้ body จริงส่วนที่ไม่ได้ capture กลับมา
- ถ้าไม่ใช่ JSON แท็บจะแสดงเป็น Body ตามเนื้อหา

### 9.5 สถานะที่ควรรู้

| สิ่งที่เห็น | ความหมาย / สิ่งที่ทำต่อ |
| --- | --- |
| **Encrypted / CONNECT** | เห็น connection HTTPS แต่ยังไม่ได้ถอดรหัส เปิด decryption และ reconnect |
| **pending** | ยังรอคำตอบ ตรวจว่า server ช้าหรือมี breakpoint |
| **Ⅱ REQ / Ⅱ RES** | หยุดอยู่ที่ request/response breakpoint เปิด Paused Traffic เพื่อ Continue หรือ Cancel |
| **Source: Map Local** | response ใช้ mock สำเร็จจริง ตรวจตรงนี้เพื่อยืนยันกฎ |
| **Source: —** | ไม่มีข้อมูลยืนยันว่าใช้ Map Local อย่าเดาจากการมีกฎอย่างเดียว |
| ข้อความ truncated/streamed/encoded/binary | มีข้อจำกัดการเก็บ body ไม่ได้หมายความว่า server ตอบ body ว่าง |

Body preview จำกัด 256 KiB ต่อ message และอาจถูกนำออกก่อน metadata เมื่อพื้นที่เต็ม ดู [ขีดจำกัดทั้งหมด](#storage) ก่อนใช้ preview ยืนยันว่าได้รับข้อมูลครบ

<a id="filters"></a>

## 10. ค้นหา กรอง บันทึกตัวกรอง และปักหมุด

### 10.1 ค้นหาแบบเริ่มต้น

กด **⌘F** เพื่อไปช่อง **Search traffic…** พิมพ์คำจาก URL, method, status หรือ error กด Escape เพื่อล้างคำค้น หากยังไม่เห็นรายการ ให้กลับ **All Traffic** เพราะ sidebar scope และคำค้นทำงานร่วมกัน

ตัวกรองมีผลต่อรายการที่แสดง ไม่ block request และไม่หยุด capture

### 10.2 Structured filters

| ตัวกรอง | ตัวอย่าง | การจับคู่ |
| --- | --- | --- |
| `host` | `host:api.example.com` | ชื่อ host ตรงตัว ไม่สนตัวพิมพ์เล็ก/ใหญ่ |
| `path` | `path:/v1/products` | substring ใน percent-encoded path พร้อม query |
| `method` | `method:POST` | method ตรงตัว ไม่สนตัวพิมพ์เล็ก/ใหญ่ |
| `status` | `status:404` หรือ `status:400-499` | รหัส 100–599 หรือช่วงที่รวมค่าต้นและท้าย |
| `type` | `type:json` | substring ของ response Content-Type จริง |
| `state` | `state:paused-request` | สถานะตรงตัว |
| `-` หน้าตัวกรอง | `-method:OPTIONS` | ซ่อนรายการที่ตรงเงื่อนไขนั้น |

state ที่รองรับคือ `pending`, `complete`, `error`, `paused-request`, `paused-response` และ `tls-passthrough`

ตัวอย่างที่คัดลอกไปลองได้ โดยแทน host/path ให้ตรงกับระบบของคุณ:

```text
host:api.example.com method:POST
host:api.example.com status:400-499
path:/products type:json -method:OPTIONS
state:paused-response
state:tls-passthrough
path:"/search?q=hello world"
```

ทุกเงื่อนไขรวมแบบ **AND** เช่นบรรทัดแรกต้องเป็น host นั้นและเป็น POST พร้อมกัน เมื่อเลือก domain/path/client ใน sidebar จะต้องผ่าน scope นั้นด้วย

ไม่มี OR, วงเล็บ หรือ regex หากใช้ `host` ซ้ำเพื่อหวังให้เลือกได้สองโดเมน จะกลายเป็น AND และอาจไม่เหลือรายการ ค่าที่มีช่องว่างให้ครอบด้วย double quotes และ escape เครื่องหมาย quote/backslash ด้วย `\"` / `\\`

ค่าที่ไม่มีข้อมูลไม่ผ่านตัวกรองแบบรวม แต่ผ่านตัวกรองแบบตัดออก เช่น pending ยังไม่มี status จะไม่ตรง `status:200` ส่วน `-status:500` ไม่ได้ตัด pending ทิ้ง

ถ้า query ผิด เช่น `status:999`, field ไม่รู้จัก หรือ quote ไม่ครบ จะแสดง error และใช้ **query ล่าสุดที่ถูกต้อง** ต่อไป รวมถึงกับ traffic ใหม่ ให้แก้ข้อความหรือล้างก่อนเพิ่มเงื่อนไขจากปุ่ม

### 10.3 ใช้ปุ่มช่วยสร้าง filter

1. กด **Add Filter**
2. เลือก Field และใส่ Value
3. เปิด **Exclude matching traffic (display only)** หากต้องการซ่อนรายการที่ตรง
4. กด **Add**
5. เงื่อนไขจะแสดงเป็นป้ายใต้ช่องค้นหา คลิกป้ายเพื่อสลับ include/exclude หรือกดกากบาทเพื่อลบ

อีกทางคือคลิกขวาที่ request → **Include / Exclude** แล้วเลือกค่าจากรายการนั้น

### 10.4 บันทึกตัวกรองไว้ใช้ซ้ำ

1. เลือก sidebar scope และพิมพ์ query ให้ได้ผลตามต้องการ
2. กด **Save…** ตั้งชื่อ เช่น `Product API errors` แล้ว Save
3. ครั้งต่อไปเปิด **Saved Filters → ชื่อตัวกรอง → Apply**
4. ใช้ **Rename… / Delete** ในเมนูเพื่อจัดการ
5. หากปรับ query/scope ของ filter ที่ใช้อยู่ จะมี `(modified)` กด **Update** เพื่อแทนค่าที่บันทึกไว้ หรือ Save เป็นชื่อใหม่

Saved filter เก็บชื่อ, query และ sidebar scope ข้ามการเปิดแอป ไม่ได้เก็บ traffic, sort หรือ pin จึงไม่ใช่การบันทึก session

### 10.5 เลือกหลายแถวและปักหมุด

ใช้ **⌘-click** เลือกหลายแถวแยกกัน หรือ **Shift-click** เลือกเป็นช่วง Inspector แสดงรายละเอียด primary request ไม่ได้รวม body ทุกแถว ระบบยึด flow ID จึงไม่เปลี่ยนเป้าหมายตาม sort

ถ้า filter ซ่อนแถวที่เลือก Inspector อาจยังแสดงรายการเดิม พร้อมข้อความว่า hidden by filters/Inspecting hidden request กด **Deselect All** เพื่อล้าง selection ทั้งที่เห็นและที่ซ่อน

คลิกขวา → **Pin Selected / Unpin Selected** เพื่อให้กลุ่มที่ปักหมุดอยู่ก่อนกลุ่มอื่น ภายในกลุ่มยังเรียงตาม sort ปัจจุบัน แถว pin มี `★` แต่ pin ไม่ข้าม filter หรือขีดจำกัด retention และไม่เก็บข้ามการเปิดแอป

Pin domain ใน sidebar เป็นคนละอย่างกับ pin request: domain pin จำข้ามการเปิดแอป ส่วน request pin เป็นของรอบใช้งานนั้น Clear หรือเริ่ม capture ใหม่ล้าง request pin/selection

เมื่อเลือกเพียงแถวบนสุดและไม่มี request pin รายการใหม่สามารถเลื่อนการเลือกตามแถวบนสุดของ sort ปัจจุบันได้ หากต้องการอ่านรายการเดิมต่อให้เลือกแถวอื่นหรือใช้ pin การเปลี่ยน filter/sort/pin เองไม่ได้ทำให้เลือก request ใหม่อัตโนมัติ

<a id="map-local"></a>

## 11. Map Local: จำลองผลลัพธ์ API

ใช้เมื่อต้องการทดสอบหน้าจอโดยกำหนดคำตอบเอง เช่นสินค้าหมด, ยอดเงินเป็นศูนย์, server error หรือข้อมูลจำนวนมาก โดยไม่ต้องแก้ข้อมูลจริงบน server

กฎเริ่มใช้อัตโนมัติหลังแก้ไขและบันทึกสำเร็จ ไม่ต้อง restart capture ให้ส่ง request ใหม่เพื่อตรวจผล

### 11.1 สร้างจาก request ที่จับได้

1. เรียก API เป้าหมายให้ปรากฏในตาราง สำหรับ HTTPS ให้เปิด decryption ก่อน
2. คลิกขวาที่แถวเป้าหมาย → **Map Local…**
3. หน้าต่าง Map Local จะสร้างกฎพร้อม host, path/query, method, status และ response headers ที่เหมาะสมจากแถวนั้น
4. ตั้ง **Name** ให้อ่านรู้เรื่อง เช่น `Products - empty list`
5. ตรวจ **Enabled**, **Host**, **Path + query** และ **Method** ว่าตรงกับ request ที่ต้องการ
6. ตั้ง **Status** เช่น `200` และกาง **Response headers** ใส่ `Content-Type: application/json` ถ้าจะตอบ JSON
7. เลือก **Body source → Text / JSON** แล้วใส่ body ตัวอย่างด้านล่าง
8. หยุดพิมพ์ประมาณ 0.5 วินาที รอข้อความสถานะบันทึกสำเร็จ หากมี error ต้องแก้ก่อน
9. กลับไปทำ action ใน client ให้เรียก API ใหม่ แล้วตรวจแถวใหม่นั้น

```json
{
  "items": [],
  "total": 0,
  "message": "ข้อมูลจำลองสำหรับทดสอบหน้าว่าง"
}
```

ตัวอย่าง body นี้ต้องปรับโครงสร้างให้ตรงกับสัญญา API ของแอปคุณ แอปอาจอ่านข้อมูลไม่ได้ถ้า response ไม่ตรง schema แม้เป็น JSON ที่ถูกต้อง

**ตรวจผล:** คอลัมน์ **Source** ของแถวใหม่ต้องเป็น **Map Local** และ Response ต้องเป็นค่าที่กำหนด จากนั้นตรวจหน้าจอ client ว่าแสดงผลตามกรณีทดสอบ

หากข้อมูลต้นฉบับเป็นข้อความครบถ้วน แอปจะช่วยเติม response body ให้ หากถูกตัด, เป็น stream, encoded/binary หรือข้อมูลเก่าไม่ยืนยันความครบถ้วน จะให้ป้อน body เอง เพื่อไม่เอา preview ที่ขาดไปใช้แทน API จริง Headers เกี่ยวกับขนาด/encoding/connection ที่ไม่เหมาะกับ mock จะไม่ถูกคัดลอกมาจากแถว

### 11.2 สร้างกฎเอง

กด **Map Local → Add** แล้วกรอกช่องตามนี้:

| ช่อง | ตัวอย่าง | สิ่งที่ต้องรู้ |
| --- | --- | --- |
| **Enabled** | เปิด | ปิดเพื่อเก็บกฎไว้แต่ไม่ใช้ |
| **Name** | `Products - empty list` | ชื่ออธิบายกรณีทดสอบ |
| **Host** | `api.example.com` | ใส่ชื่อ host ไม่ใส่ `https://` |
| **Path + query** | `/v1/products*` | รวม query ในการจับคู่ ใช้ wildcard เมื่ออยากรับหลายค่า |
| **Method** | `GET` | `*` หมายถึงทุก method |
| **Status** | `200` หรือ `500` | รหัสที่ต้องการให้ client ได้รับ |
| **Delay (ms)** | `1500` | หน่วง response จำลอง 1.5 วินาที ใช้ทดสอบ loading |
| **Response headers** | `Content-Type: application/json` | หนึ่งบรรทัดต่อ `Name: value` |
| **Body source** | `Text / JSON` หรือ `File` | กำหนดเนื้อหาคำตอบ |

Host/path ใช้ `*` แทนข้อความกี่ตัวก็ได้ และ `?` แทนหนึ่งตัวอักษร นี่เป็น pattern matching ต่างจาก `path:` ในช่องค้นหาที่เป็น substring ระวังตั้งกว้างเกินไป เช่น `*` อาจครอบคลุมหลาย API

ถ้า API เรียก `/v1/products?page=1` แต่กฎเป็น `/v1/products` อย่างเดียว อาจไม่ตรงเพราะ query อยู่ในเงื่อนไขด้วย ตรวจ request จริง หรือใช้ `/v1/products*` เมื่อยอมให้ครอบคลุม query/ส่วนต่อท้ายเหล่านั้น

### 11.3 ตัวอย่างกรณีทดสอบ

- **หน้าว่าง:** Status `200`, body เป็นโครงสร้างข้อมูลว่างตาม schema จริง
- **ข้อผิดพลาด:** Status `500`, body เป็น error ที่แอปรองรับ เช่น `{"code":"TEST_ERROR","message":"ลองใหม่อีกครั้ง"}`
- **Loading:** เพิ่ม Delay เช่น `1500` ms แล้วตรวจ loading ของ client นี่เป็น delay ของ mock ไม่ใช่เครื่องมือจำลองความเร็วเครือข่ายทั้งระบบ

### 11.4 Text / JSON editor และ File

**Text / JSON** พิมพ์หรือวางข้อความได้ กด **Format JSON** เพื่อจัดรูปแบบ, **Collapse All / Expand All** เพื่อพับ/ขยาย มีเลขบรรทัดและ syntax colors กด Enter เพื่อย่อหน้าตามระดับ, Tab เพิ่ม 2 spaces และ Shift+Tab ลดย่อหน้า รองรับ undo/redo

ถ้า JSON ไม่ถูกต้อง Format จะแจ้ง error และรักษาข้อความเดิม ยังใช้ plain text, body ว่าง หรือ JSON ที่ตั้งใจให้ผิดเพื่อทดสอบได้ การพับไม่เปลี่ยน body ที่บันทึก และเริ่มแก้จะขยายกลับให้

**File** ใช้ **Choose Response File…** เลือกไฟล์ได้รวมถึง binary แอปคัดลอกไฟล์ไปยัง managed mock storage จึงย้ายไฟล์ต้นฉบับได้ หากแก้ไฟล์ต้นฉบับภายหลังต้องเลือกไฟล์ใหม่เพื่ออัปเดต mock

Text และ File จำกัด body 8 MiB ต่อกฎ การสลับไฟล์ UTF-8 มา Text / JSON โหลดมาแก้ได้ แต่ binary จะสลับไม่ได้และคง File mode การเปิดอ่าน body ไม่ได้เขียนไฟล์ใหม่เอง ส่วนข้อความที่แก้จะบันทึกอัตโนมัติเป็น managed mock file

### 11.5 หลายกฎ ลำดับ และการบันทึก

กฎ Map Local ใช้ **กฎแรกที่เปิดและตรงเงื่อนไข** ถ้ากฎกว้างอยู่ก่อนกฎเฉพาะ กฎเฉพาะอาจไม่ได้ทำงาน ใช้ **↑ / ↓** เปลี่ยนลำดับหลังล้างช่องค้นหากฎ หมายเลข `#` เป็นลำดับจริง ไม่เปลี่ยนตามผลค้นหา

ค้นหากฎจาก name/host/path/method/status ได้ ใช้ **Duplicate** เพื่อทำสำเนาถัดจากต้นฉบับ แล้วแก้เงื่อนไขหรือปิดกฎเดิม มิฉะนั้นต้นฉบับอาจถูกเลือกก่อนเสมอ เลือกหลายกฎด้วย ⌘/Shift-click แล้วกด **Delete** เพื่อลบกฎที่เลือก

การแก้รวมถึง checkbox บันทึกและอัปเดต engine หลังหยุดแก้ประมาณ 0.5 วินาที หาก validation ไม่ผ่าน engine ใช้กฎที่บันทึกสำเร็จล่าสุดต่อไป ปุ่ม **Close** ปิดหน้าต่างโดยการแก้ล่าสุดยังถูกบันทึก กฎอยู่ต่อหลัง Stop/Start, Clear และเปิดแอปใหม่ ดังนั้นจบการทดสอบให้ปิดกฎที่ไม่ต้องการใช้

Map Local รองรับ request body ที่ทราบขนาดไม่เกิน 1 MiB; streaming upload ที่ตรงกฎจะถูกยกเลิกพร้อมเหตุผลแทนการส่งต่อ บาง client อาจรอ timeout ถ้า managed mock file หายจะตอบ 502

<a id="rule-transfer"></a>

## 12. นำเข้าและส่งออกกฎ Map Local

### 12.1 ส่งกฎให้เพื่อนร่วมทีม

1. เปิด **Map Local**
2. เลือกกฎด้วย **⌘-click / Shift-click**
3. กด **Export… → Export Selected (N)…** หรือ **Export All…** หากต้องการทั้งหมด
4. เลือกที่บันทึกไฟล์
5. ตรวจ body/headers ว่าไม่มีข้อมูลลับก่อนแชร์ ไฟล์ส่งออกมี response body รวมอยู่ด้วย

ไฟล์เป็น Reqnivo JSON รูปแบบ `Reqnivo.MapLocal` รวมทั้ง binary และข้อความที่ยังรอบันทึก ส่งเป็นไฟล์เดียวโดยไม่ต้องคัดลอก mock-files แยก และรักษาลำดับกฎ

### 12.2 นำกฎกลับเข้า Reqnivo

1. เปิด **Map Local → Import…**
2. เลือกไฟล์ที่ต้องการ
3. ถ้านำเข้าสำเร็จ กฎจะต่อท้ายรายการเดิมและบันทึกอัตโนมัติ
4. ตรวจ Enabled และลำดับก่อนเรียก API โดยเฉพาะกรณีกฎเก่าตรง endpoint เดียวกัน
5. เรียก API ใหม่ แล้วตรวจ **Source: Map Local**

Import เป็นการเพิ่ม ไม่แทนกฎเดิมทั้งหมด และกฎที่เปิดใช้งานจะมีผลหลังนำเข้าสำเร็จ

### 12.3 รูปแบบไฟล์และขีดจำกัด

รองรับไฟล์ `.config` ที่มี `mapLocalData` และ JSON tree ของ Map Local แบบแยก กฎในโฟลเดอร์จะคลี่ตามลำดับเดิมและรักษาสถานะปิดของโฟลเดอร์ กฎเครื่องมือชนิดอื่นใน backup ไม่ถูกนำเข้า

กฎที่นำเข้าจากรูปแบบนี้ใช้ **URL pattern / Include subpaths** เพื่อคง protocol, port และ query; หลาย methods แยกเป็นหลายกฎ รองรับ wildcard และ response ที่ฝังมาเป็น raw file หรือ HTTP message

หากมี Regex, Directory, GraphQL, `FILE_URL` ภายนอก หรือ response file ไม่ได้ฝังมา จะยกเลิกการนำเข้าทั้งชุดพร้อมแจ้งเหตุผลก่อนเปลี่ยนรายการ Import จำกัดไฟล์ 256 MiB, body 8 MiB ต่อกฎ และกฎทุกชนิดรวมสูงสุด 200 กฎ Export เป็น format ของ Reqnivo สำหรับนำกลับเข้า Reqnivo

<a id="breakpoints"></a>

## 13. Breakpoint: หยุดและแก้ request/response

Map Local เหมาะกับคำตอบจำลองที่ใช้ซ้ำ ส่วน Breakpoint เหมาะกับการหยุดแต่ละรายการเพื่อเปลี่ยนค่าก่อนส่งต่อ เช่นแก้จำนวนสินค้าใน request หรือแก้ status/body ของ response ที่ server ตอบมา

### 13.1 สร้างกฎหยุด request

1. คลิกขวา request เป้าหมายเพื่อสร้างกฎ breakpoint จากแถวนั้น หรือกด **Breakpoints → Add**
2. ตั้ง Name, Host, Path + query และ Method ให้แคบตรง API ที่ต้องการ
3. เปิด **Enabled**
4. ใน **Pause** เปิด **Pause request before forwarding** ถ้าต้องการแก้ก่อนส่งถึง server
5. ปิด **Pause response before returning** ถ้ายังไม่ต้องการหยุดขาตอบ
6. รอการบันทึกอัตโนมัติสำเร็จ แล้วเรียก API ใหม่จาก client

**ตรวจผล:** แถวจะมี `Ⅱ REQ` และ client รอผล หน้าต่าง **Paused Traffic** เปิดอัตโนมัติเมื่อมีรายการหยุดใหม่ หรือเปิดผ่าน **Breakpoints → Paused Traffic (N)** แล้วเลือกรายการทางซ้ายเพื่อแก้ด้านขวา

### 13.2 แก้ request แล้วส่งต่อ

1. ตรวจหัว editor ว่าเป็น **REQUEST** และ URL ถูกตัว
2. แก้ **Method / URL** หากต้องการเปลี่ยนปลายทางหรือ query
3. กาง **Headers** เพื่อแก้ค่า ใช้ **Add Header** เพิ่ม หรือปุ่มลบเพื่อนำออก
4. แก้ **Body** เมื่อ editor อนุญาต เช่นเปลี่ยน `quantity` จาก `1` เป็น `2` ให้ตรง schema ของ API
5. กด **Continue** เพื่อใช้ค่าที่แก้และส่งต่อ
6. ตรวจผลจาก server และหน้าจอ client

ค่าที่แก้จะส่งไปใช้เมื่อกด Continue เท่านั้น ปุ่ม **Close** เก็บ draft และยังคงหยุด traffic อยู่ ส่วน **Cancel Request** ยกเลิก flow นั้น client จะไม่ได้ response ปกติ

### 13.3 หยุดและแก้ response

1. เปิดกฎเดียวกันหรือสร้างกฎใหม่
2. เปิด **Pause response before returning** และปิด pause request หากต้องการหยุดเฉพาะขาตอบ
3. เรียก API ใหม่ รอจน server ตอบและแถวขึ้น `Ⅱ RES`
4. เปิด Paused Traffic เลือกรายการ ตรวจหัว editor ว่าเป็น **RESPONSE**
5. แก้ **Status**, Headers และ Body ที่แก้ได้ เช่นเปลี่ยนเป็น error ตาม schema ที่ client รองรับ
6. กด **Continue** แล้วตรวจว่าหน้าจอ client ตอบสนองต่อค่าที่แก้ตามคาด

ถ้าเปิดหยุดทั้ง request และ response รายการเดียวอาจต้อง Continue สองครั้ง: ครั้งแรกปล่อย request ไป server และครั้งที่สองปล่อย response กลับ client

### 13.4 สิ่งที่ต้องรู้ขณะมีรายการค้าง

- ปิดหน้าต่างหรือปิด checkbox ของกฎไม่ได้ปล่อยรายการที่หยุดอยู่ ต้อง Continue หรือ Cancel เอง
- การแก้กฎมีผลกับการจับคู่ครั้งถัดไป ไม่แก้รายการที่ค้างย้อนหลัง
- Stop หรือปิดแอปจะยกเลิกรายการที่ค้าง ไม่ใช่การส่งต่อให้เสร็จ
- หยุดรอได้สูงสุด 32 รายการ เมื่อเต็ม รายการที่ตรงเพิ่มจะถูกยกเลิก
- client อาจ timeout ระหว่างที่เราหยุดแก้ จึงควรหยุดเฉพาะ endpoint ที่ต้องการ
- แก้ body ได้เฉพาะ UTF-8 text/JSON ที่ครบและไม่เกิน 256 KiB; encoded/binary/streamed body จะคง bytes เดิม ถึงแก้ body ไม่ได้ก็ยังตรวจและแก้ช่องที่ editor เปิดให้ได้

chunked JSON ที่ไม่บีบอัดสามารถรอ body ครบเพื่อแก้ได้ตามขีดจำกัด ส่วนข้อมูลที่คาดว่าจะ stream จะหยุดก่อนส่ง headers และแก้ body ไม่ได้ chunked JSON ที่เกิน engine buffer 1 MiB จะหยุดก่อนเริ่ม stream

### 13.5 เมื่อใช้ร่วมกับ Map Local

ลำดับคือ **request breakpoint → Map Local → response breakpoint** หากแก้ URL ใน request breakpoint การจับคู่ Map Local ใช้ URL หลังแก้ ดังนั้น response ที่หยุดขาตอบอาจเป็น mock จาก Map Local ได้ด้วย

<a id="settings"></a>

## 14. Capture Settings และ CA ของเซิร์ฟเวอร์

เปิดด้วยปุ่ม **Settings** หรือเมนูแอป **Capture Settings…** และ **⌘,**

| ตัวเลือก | ความหมาย / เวลาแก้ |
| --- | --- |
| **Proxy port** | port ที่ client ใช้เชื่อมต่อ เช่น 9090; Stop ก่อนเปลี่ยน แล้วแก้ client ให้ตรง |
| **Control port (localhost only)** | port ภายในที่ UI คุยกับ engine เช่น 9091; ไม่ใช้เป็น proxy บนมือถือ และต้องต่างจาก Proxy port |
| **Allow test devices on local network** | เปิด listener บนทุก IPv4 interface ให้ client ใน LAN เชื่อมต่อ; Stop ก่อนเปลี่ยน |
| **Mac network service** | service ที่แอปจะเปลี่ยน system proxy เช่น Wi-Fi; Stop ก่อนเปลี่ยน |
| **Capture Mac Traffic** | เปิด/ปิด Mac system proxy ได้ระหว่าง capture |
| **Skip server certificate verification (debug only)** | ข้ามการตรวจ certificate/hostname ฝั่งเซิร์ฟเวอร์สำหรับ HTTPS ที่ถอดรหัส; Stop ก่อนเปลี่ยน |
| **Choose CA File… / Replace CA File…** | เพิ่ม PEM CA bundle ขององค์กรให้ engine ตรวจ server ได้ โดยต้องปิด Skip ก่อน |
| **Remove Custom CA** | กลับไปใช้ CA มาตรฐานของ engine |
| **Restore Mac Proxy** | แสดงเมื่อมี recovery ที่ต้องจัดการ ใช้คืนค่า proxy ที่แอปบันทึกไว้ |

### 14.1 CA ของ client กับ CA ของ server ต่างกันอย่างไร

**Show Public CA Certificate** ใช้ให้ client เช่นโทรศัพท์เชื่อถือ Reqnivo ส่วน **Choose CA File…** ใช้ให้ Reqnivo เชื่อถือ server ภายในองค์กร การเพิ่ม CA ฝั่งหนึ่งไม่ได้แก้อีกฝั่ง

ถ้า API ภายในขึ้น `self-signed certificate in certificate chain` ให้ขอ PEM CA/bundle ของ server จากทีมที่ดูแล แล้วทำดังนี้:

1. Stop capture และเปิด Settings
2. ปิด **Skip server certificate verification (debug only)** หากเปิดอยู่
3. กด **Choose CA File…** หรือ Replace เพื่อเลือก PEM bundle
4. Start capture ใหม่ แล้วเรียก API ตรวจผล

แอปเก็บสำเนา CA และใช้ร่วมกับ CA มาตรฐานของ engine โดยยังตรวจ hostname/certificate ไม่ได้ติดตั้งไฟล์นี้ลง Keychain หรือโทรศัพท์

### 14.2 ตัวเลือก Skip ใช้เมื่อไร

ใช้ในงาน debug ที่ต้องข้ามการตรวจ certificate/hostname ของ server ชั่วคราว ต้อง Stop → เปลี่ยนตัวเลือก → Start ใหม่ มีผลครอบคลุมปลายทาง HTTPS ที่ถอดรหัสใน capture รอบนั้น ไม่ใช่เฉพาะ request แถวเดียว และยังต้องให้ client trust Reqnivo CA ตามปกติ

ค่าตั้งต้นใน settings ใหม่ปิด Skip และค่าที่บันทึกไว้จะถูกโหลดกลับ ให้ตรวจ checkbox ก่อนเริ่มใช้งาน ตัวเลือกนี้ไม่ทำให้ HTTPS ที่ยังไม่เปิด decryption อ่านได้ และไม่แก้ pinning ของ client

<a id="troubleshooting"></a>

## 15. แก้ปัญหาที่พบบ่อย

### 15.1 ไม่เห็น traffic เลย

1. ดูว่า engine กำลัง capture และไม่มี error
2. กลับ All Traffic ล้าง search รวมทั้งตรวจ saved filter/scope
3. บน Mac ตรวจ Capture Mac Traffic และ network service หรือใช้ curl แบบระบุ proxy เพื่อแยกว่าเป็นปัญหา routing ของ client หรือไม่
4. บนมือถือ ตรวจ Proxy server/port, LAN capture และ IP ปัจจุบันของ Mac
5. ตรวจว่าโปรแกรมนั้นใช้ system/Wi-Fi proxy จริงหรือมีการตั้งค่า bypass/proxy ของตนเอง

### 15.2 เปิด `http://mitm.it` บนมือถือไม่ได้

ตรวจว่าใช้ `http://`, capture ยังทำงาน, เปิด LAN และไม่ได้ใส่ Control port โทรศัพท์ต้องเข้าถึง Mac ได้ เครือข่าย guest/client isolation อาจกันอุปกรณ์ไม่ให้คุยกัน แม้ชื่อ Wi-Fi เหมือนกัน ตรวจ VPN และ firewall ตามนโยบายเครือข่ายด้วย

ถ้าเห็นหน้าเว็บบอกว่าไม่ได้ผ่าน mitmproxy ให้ย้อนตรวจ proxy ของ client ก่อน QR เป็นลิงก์ไป mitm.it ไม่ได้ตั้ง proxy หรือติดตั้ง CA ให้อัตโนมัติ

### 15.3 เห็นแต่ CONNECT / Encrypted

แปลว่า HTTPS ยังส่งผ่านแบบเข้ารหัส เลือกแถวนั้นแล้ว Enable Decryption หรือเปิดจากเมนูโดเมน จากนั้น reconnect client การ trust CA อย่างเดียวไม่เปิด decryption และแถวเก่าจะไม่เปลี่ยนย้อนหลัง

### 15.4 เปิด decryption แล้วเว็บหรือแอปขึ้น certificate error

ตรวจว่า client ติดตั้ง CA จาก Mac เครื่องที่กำลังใช้จริง iPhone ต้องเปิด full trust; Android app ต้องมี debug trust ที่เหมาะสม บางโปรแกรมมี trust store ของตนเอง หากเปลี่ยน Mac หรือล้างโฟลเดอร์ ca แล้ว CA เปลี่ยน ต้องใช้ public CA ใหม่ ไม่พิจารณาจากชื่อ mitmproxy อย่างเดียว

ถ้า error เป็นการตรวจ server ภายใน ให้ดู [CA ฝั่งเซิร์ฟเวอร์](#settings) แยกจากการ trust บน client

### 15.5 Safari/Chrome ใช้ได้ แต่แอปทดสอบใช้ไม่ได้

ตรวจว่าแอปผ่าน proxy และเชื่อถือ user CA หรือไม่ อาจมี certificate pinning หรือ network stack ที่ใช้ configuration ของตัวเอง ให้ทีมปรับเฉพาะ debug build ของแอปที่ได้รับอนุญาต แล้วทดสอบใหม่

### 15.6 Map Local ไม่ทำงาน หรือได้ response ของกฎอื่น

1. ตรวจว่า Enabled และการบันทึกไม่มี error
2. HTTPS ต้องเปิด decryption ก่อน
3. เทียบ host, method, path **รวม query** กับ request จริง
4. ตรวจว่ามีกฎที่ตรงและอยู่ก่อนหรือไม่ ล้าง search ก่อนปรับ ↑/↓
5. ตรวจว่า flow ค้าง request breakpoint หรือถูกยกเลิกก่อนใช้ mock หรือไม่
6. ส่ง request ใหม่ แล้วดู Source: Map Local หากได้ 502 ตรวจว่าไฟล์ mock ยังอ่านได้

### 15.7 แก้ body แล้วผลไม่เปลี่ยน

Map Local ต้องรอบันทึกสำเร็จและเรียกใหม่ การดู request เก่าไม่เปลี่ยนข้อมูลเดิม ส่วน Breakpoint ต้องกด Continue จึงใช้ draft ถ้า client มี cache หรือไม่ได้เรียก API ซ้ำ ให้ทำ action ที่ส่ง request จริง

### 15.8 แอปทดสอบค้าง loading

ดูตัวเลขบน Breakpoints และ Paused Traffic ว่ามี request/response หยุดอยู่หรือไม่ Continue หรือ Cancel รายการนั้น การปิดหน้าต่าง editor ไม่ได้ปล่อย traffic และการปิดกฎมีผลต่อรายการใหม่เท่านั้น

### 15.9 Body ว่าง ถูกตัด หรือแก้ไม่ได้

ตรวจว่าเป็น request ที่ไม่มี body ตามปกติหรือไม่ ถัดมาดู capture state: truncated, streamed, encoded หรือ binary รุ่นนี้ไม่แสดง compressed/binary body และ body ใหญ่มีขีดจำกัด อย่าใช้ preview ที่ขาดเป็นหลักฐานว่า server ส่งข้อมูลไม่ครบ

### 15.10 Start ไม่ได้เพราะ port ถูกใช้

Stop แล้วเปิด Settings เปลี่ยน Proxy/Control port ให้เป็น port ว่างและต่างกัน เช่น 9190/9191 จากนั้น Start ใหม่และแก้ proxy port ที่ client ทุกเครื่องตาม ไม่ต้องนำ Control port ไปใส่ที่ client

### 15.11 ปุ่มตั้ง port/LAN/CA เป็นสีเทา

ตัวเลือกเหล่านี้แก้ได้เมื่อหยุด capture และแอปไม่ busy กด Stop แล้วรอให้เสร็จก่อน ส่วน custom CA จะถูกปิดไว้ขณะที่เปิด Skip server certificate verification

### 15.12 ไม่พบ Simulator หรืออุปกรณ์ ADB

Simulator ต้อง boot แล้ว; Android ต้องมี Platform-Tools และอนุญาต USB debugging หากเป็น unauthorized ให้ยืนยันบนอุปกรณ์แล้ว Refresh ใหม่ root ไม่ได้ให้ใช้ Copy CA & Open Settings แทน Install CA Automatically

### 15.13 เปลี่ยน filter แล้วเหมือน Inspector แสดงผิดแถว

ตรวจข้อความ hidden by filters/Inspecting hidden request ระบบรักษา request ที่เลือกไว้ แม้ตัวกรองซ่อนมัน กด Deselect All แล้วเลือกแถวที่ต้องการใหม่ หรือคืน filter เพื่อให้แถวเดิมปรากฏ

### 15.14 ปิด capture แล้วอินเทอร์เน็ตยังใช้ไม่ได้

บนโทรศัพท์คืน Wi-Fi proxy เป็นค่าเดิม บน Mac เปิดแอปและดู Settings → Restore Mac Proxy ถ้ามี recovery หากยังคืนไม่ได้ให้ตรวจ **System Settings → Network → service ที่ใช้ → Details → Proxies** โดยเทียบค่าก่อนทดสอบ อย่าปิด proxy องค์กรที่มีอยู่เดิมโดยไม่ตรวจสอบ

แอปแก้เฉพาะ service ที่เลือก ไม่แก้ PAC/bypass list และไม่เขียนทับ endpoint ที่โปรแกรมอื่นเปลี่ยนระหว่าง capture หากคืนไม่ได้จะเก็บ recovery record ให้จัดการต่อ รายละเอียดดูบทถัดไป

<a id="cleanup"></a>

## 16. จบการทดสอบและคืนค่าเครือข่าย

1. ปิด checkbox ของ Map Local/Breakpoint ที่ไม่ต้องการให้ใช้ต่อ เพราะกฎจำข้ามการเปิดแอป
2. จัดการรายการใน Paused Traffic ด้วย Continue หรือ Cancel ถ้าจะ Stop ทันทีให้ทราบว่ารายการที่ค้างจะถูกยกเลิก
3. กด **Stop** แอปพยายามคืน Mac proxy ที่ตัวเองเปลี่ยน
4. ตรวจสถานะ Mac proxy หากยังต้อง recovery ใช้ **Settings → Restore Mac Proxy** และตรวจผลก่อนลบข้อมูลแอป
5. บนโทรศัพท์/emulator คืน proxy เป็นค่าเดิม การ Stop บน Mac ไม่ได้แก้ Wi-Fi proxy บนมือถือให้
6. ลบ CA/profile ออกจากอุปกรณ์หรือ trust store ที่ติดตั้งเมื่อไม่ใช้แล้ว บน Mac ตรวจผ่าน Keychain Access บนมือถือใช้ Settings
7. หากต้องเก็บหลักฐานงาน ให้คัดลอกเฉพาะข้อมูลที่ได้รับอนุญาตและตรวจข้อมูลลับก่อน ปัจจุบันยังไม่มีการบันทึก/นำเข้า/ส่งออก capture session
8. ปิดแอปตามปกติ หาก macOS แจ้งว่ายังต้องคืน proxy ให้เลือกเก็บแอปเปิดไว้เพื่อ retry หรือจัดการใน Network Settings

หากแอป crash/ถูก force quit ให้เปิดกลับมาเพื่อให้ตรวจ recovery record ก่อน ระบบไม่เปลี่ยนทับ endpoint ที่โปรแกรมอื่นแก้ไปแล้ว และ proxy ที่มี authentication เดิมอาจถูกปฏิเสธเพื่อไม่ทำข้อมูล authentication หาย

**Clear** ไม่เท่ากับลบข้อมูลส่วนบุคคลทั้งหมด และลบ Reqnivo.app อย่างเดียวไม่ลบ Application Support หรือ CA ที่ติดตั้งไว้ หากต้อง reset ให้คืน proxy และถอน CA ก่อนปิดแอปแล้วจัดการข้อมูลตาม [Privacy and local data](PRIVACY.md) ระวังว่าการล้าง ca จะเปลี่ยน CA เมื่อสร้างใหม่

<a id="storage"></a>

## 17. ข้อมูลที่บันทึกและข้อจำกัด

### 17.1 ตำแหน่งข้อมูล

ค่าเริ่มต้นอยู่ใน `~/Library/Application Support/Reqnivo/` เปิด Finder → **Go → Go to Folder…** แล้ววาง path นี้ได้ หากตั้ง `REQNIVO_DATA_DIR` จะใช้ directory นั้นแทน

| ข้อมูล | ที่เก็บ / อายุข้อมูล |
| --- | --- |
| การตั้งค่า | `settings.json`: port, LAN, Mac capture/service, TLS verification, domain pin, HTTPS domain choices และตำแหน่ง Inspector/Request–Response |
| Saved filters | `traffic-filters.json`: query, ชื่อและ scope ไม่เก็บ traffic |
| กฎ | `rules.json`: โหลดกลับเมื่อเปิดแอป; Stop/Start/Clear ไม่ลบ |
| ไฟล์ mock | `mock-files/`: managed response files อาจมีข้อมูลลับจาก API |
| CA | `ca/`: public certificate และ private key เก็บใช้ซ้ำ |
| Capture previews | `captures/`: previews/summary บนดิสก์ มีขีดจำกัดและล้างตาม lifecycle |
| ข้อมูลอื่น | custom upstream CA, engine log และ proxy recovery record ไม่มีคำรับรองว่าลบอัตโนมัติในระยะเวลาคงที่ |

ห้ามแชร์ CA private key ใช้เฉพาะ public `mitmproxy-ca-cert.pem` เมื่อติดตั้งให้ client ไฟล์ `mitmproxy-ca.pem` มี private key รวมอยู่ด้วย

ข้อมูล capture ไม่ถูกเข้ารหัสโดย Reqnivo และไม่ได้ redact อัตโนมัติ แม้ directory มี private permissions ผู้ที่เข้าถึงบัญชี, สิทธิ์ผู้ดูแล หรือ backups ยังอาจเข้าถึงได้

### 17.2 ขีดจำกัดที่มีผลกับการใช้งาน

| รายการ | ขีดจำกัด / ผลต่อผู้ใช้ |
| --- | --- |
| ประวัติบน UI | สูงสุด 10,000 flows แบบ rolling; pin ไม่กันถูกนำออก |
| Engine events | ล่าสุดไม่เกิน 30,000 events |
| Body preview | 256 KiB ต่อ message ไม่ใช่ full-body archive |
| Body ขนาดใหญ่ | เกิน 1 MiB ให้ stream ผ่าน ไม่เก็บทั้งก้อน; ไม่ตัด traffic จริงตาม preview |
| Preview storage | 128 MiB บนดิสก์; detail อาจถูกนำออกก่อน metadata |
| Body บีบอัด/binary | ยังไม่แสดง body ใน inspector แต่ยังตรวจ headers ได้ |
| Map Local body | 8 MiB ต่อกฎ รองรับ Text/File รวม binary |
| Request ที่ใช้ Map Local | ต้องทราบขนาด body ไม่เกิน 1 MiB; streaming upload ที่ตรงกฎถูกยกเลิก |
| แก้ body ที่ breakpoint | UTF-8 text/JSON ครบถ้วนไม่เกิน 256 KiB |
| รายการหยุดรอ | สูงสุด 32 รายการ เพิ่มเกินนี้ถูกยกเลิก |
| กฎทุกชนิดรวมกัน | สูงสุด 200 กฎ |
| Import Map Local | ไฟล์ไม่เกิน 256 MiB และ body 8 MiB ต่อกฎ |
| WebSocket | ส่งผ่านได้ ยังไม่มี message inspector |
| Capture session | ยังไม่มี save/import/export |

KiB/MiB เป็นหน่วยฐาน 1024 เช่น 256 KiB = 262,144 bytes

หลัง Stop ยังอ่าน preview ปัจจุบันได้ แต่เริ่ม capture ใหม่จะล้าง preview เก่า และปิดแอปตามปกติจะลบ directory ของ capture ปัจจุบัน Crash, force quit หรือ cleanup failure อาจทิ้งไฟล์ไว้ การเปิด capture owner ใหม่จะล้าง directory เก่าตาม lifecycle อย่าใช้โฟลเดอร์ captures เป็นที่เก็บ session ถาวร

LAN mode รับจากอุปกรณ์ที่เข้าถึง Mac ได้บนเครือข่าย ยังไม่มี allowlist รายอุปกรณ์ Control API อยู่ loopback และต้องมี per-capture bearer token ส่วนการประมวลผล capture อยู่บน Mac แอปไม่ได้มีบริการ upload capture/account/analytics ของผู้พัฒนา รายละเอียดและขอบเขตข้ออ้างนี้อยู่ใน [PRIVACY.md](PRIVACY.md)

<a id="walkthrough"></a>

## 18. แบบฝึกหัดตั้งแต่ต้นจนจบ

แบบฝึกหัดนี้ใช้ HTTP กับ `example.com` เพื่อเรียนรู้ขั้นตอนโดยยังไม่ต้องติดตั้ง CA ต้องมี Terminal และเริ่ม capture ที่ `127.0.0.1:9090` หากเปลี่ยน port ให้ปรับคำสั่งตามจริง

### 18.1 จับ request แรก

1. เปิด Reqnivo และ Start Capture
2. เลือก All Traffic และล้างคำค้น
3. ใน Terminal รัน:

```sh
curl --noproxy '' --proxy http://127.0.0.1:9090 http://example.com/
```

4. กลับมาที่ Reqnivo เลือกแถว `GET example.com /`
5. เปิด Request Headers และ Response Body เพื่อลองอ่านสองฝั่ง ไม่จำเป็นว่า server ต้องตอบ status ใดสถานะหนึ่งจึงจะตรวจ routing ได้

### 18.2 เปลี่ยนคำตอบด้วย Map Local

1. คลิกขวาแถวที่เพิ่งได้ → Map Local…
2. ตั้ง Name เป็น `Practice - hello`
3. ตรวจ Host = `example.com`, Path + query = `/`, Method = `GET`, Enabled เปิดอยู่
4. ตั้ง Status = `200`, Response headers = `Content-Type: application/json`
5. เลือก Text / JSON แล้วใส่:

```json
{"message":"สวัสดีจาก Reqnivo","step":1}
```

6. รอบันทึกสำเร็จ แล้วรัน curl คำสั่งเดิมอีกครั้ง
7. ควรได้ JSON ที่กำหนดใน Terminal และแถวใหม่มี **Source: Map Local**

### 18.3 หยุด response แล้วเปลี่ยนค่า

1. เปิด Breakpoints → Add
2. ตั้ง Name เป็น `Practice - edit response`, Host = `example.com`, Path + query = `/`, Method = `GET`
3. เปิด Enabled และ **Pause response before returning** ปิด **Pause request before forwarding**
4. รอบันทึกแล้วรัน curl เดิมอีกครั้ง Terminal จะรอ เพราะ response หยุดอยู่
5. เปิด Paused Traffic เลือกรายการ RESPONSE แล้วเปลี่ยน body เป็น:

```json
{"message":"แก้ด้วย Breakpoint แล้ว","step":2}
```

6. กด Continue ควรเห็น Terminal ได้ body ที่มี `step: 2` ซึ่งแก้เฉพาะ flow นี้ Map Local ต้นฉบับยังเป็น `step: 1`
7. ปิดกฎ breakpoint แล้วรันซ้ำ ควรกลับมาได้ `step: 1` จาก Map Local
8. ปิดกฎ Map Local แล้ว Stop เพื่อจบแบบฝึกหัด

เมื่อทำได้ครบ คุณจะตรวจทางผ่าน proxy, อ่าน request/response, ยืนยัน mock ด้วย Source และแยกการแก้ถาวรในกฎออกจากการแก้แต่ละ flow ที่ breakpoint ได้ จากนั้นใช้ [บท HTTPS](#https) และบทอุปกรณ์ที่ต้องการเพื่อตรวจแอปจริงของทีม

<a id="development"></a>

## 19. ภาคผนวกสำหรับนักพัฒนา

### 19.1 Build และเปิดแอปจาก source

บน Apple Silicon ที่มี Xcode/toolchain ตามโครงการ เปิด Terminal ใน root ของ repository:

```sh
./scripts/fetch-engine.sh
./scripts/build-app.sh
open dist/Reqnivo.app
```

build ใช้โลโก้หลัก [`images/Reqnivo-icon.png`](../images/Reqnivo-icon.png) สร้าง Reqnivo.icns สำหรับแอป, Dock และ About หากเปลี่ยนโค้ดแล้วให้ปิด/เปิดแอป build ใหม่เพื่อโหลด executable ใหม่

### 19.2 การทดสอบและวัด baseline

เลือกคำสั่งให้ตรงงาน ไม่จำเป็นต้องรันทั้งหมดเพื่อใช้งานแอป:

```sh
./scripts/swift.sh test
/usr/bin/python3 scripts/smoke-engine.py --count 100
/usr/bin/python3 scripts/smoke-rules.py
/usr/bin/python3 scripts/smoke-https-decryption.py
/usr/bin/python3 scripts/smoke-engine.py --count 10000 --output .cache/engine-https-burst.json
/usr/bin/python3 scripts/smoke-engine.py --count 300 --rate 10 \
  --app dist/Reqnivo.app --output .cache/native-paced-baseline.json
```

Integration scripts สร้าง local fixture และ test CA ชั่วคราว ไม่แก้ trust store หรือ system proxy สำหรับการตรวจ engine หากจะทดสอบ GUI ให้ Stop แอปที่ใช้งานอยู่ก่อนเพื่อไม่ชน port 9090/9091

ผล baseline เดิมอยู่ใน [BASELINE.md](BASELINE.md) มี raw JSON ให้ตรวจ CPU จาก `ps` เป็น decaying average และเวลา model ไม่ใช่ frame-render time ต้องใช้ Instruments/ทดสอบ scroll แยกก่อนสรุปความลื่น

ในแอปคลิกค่า RAM/CPU ด้านล่าง หรือเมนู **Performance Baseline…** เพื่อดู UI/engine RSS, CPU, preview storage และ latency ใช้ **Export Snapshot…** ส่งออก metrics ได้ ไฟล์นี้ไม่ใช่ capture session

### 19.3 ทดสอบตัวช่วยติดตั้ง CA บน emulator แบบ opt-in

คำสั่งนี้ติดตั้ง CA ของ Mac ลง emulator ที่ระบุจริง ต้องเลือกเครื่องทดสอบที่อนุญาต แล้วรันจาก root ของ repository:

```sh
REQNIVO_CERT_TEST_EMULATOR=emulator-5554 ./scripts/swift.sh test --filter DeviceCertificateTests
```

ตัวช่วย Android เป็น DEX ที่ bundle มากับแอป ใช้ native TrustedCertificateStore จัดการชื่อไฟล์/hash collision และตรวจ cert หลังติดตั้ง หากแก้ `scripts/android/InstallCertificate.java` ให้รัน `./scripts/build-certificate-helper.sh` ซึ่งต้องใช้ JDK 17+ และ Android SDK Build-Tools แล้ว build แอปใหม่ ผู้ใช้แอปปกติไม่ต้องมี JDK

### 19.4 โครงสร้างและรายละเอียดสำหรับตรวจพฤติกรรม

- `Sources/Reqnivo`: SwiftUI/AppKit, traffic model, process lifecycle, settings และ Mac proxy recovery
- `Sources/Reqnivo/Resources/bridge.py`: loopback control API, bearer token, body preview storage และ parent watchdog
- `scripts`: fetch engine แบบ pin version/checksum, build app และ integration/benchmark harness
- UI poll metadata เป็นชุดทุก 250 ms และโหลด detail เมื่อเลือก ไม่ส่ง body ทุกแถวเข้า UI; engine เป็น subprocess แยก lifecycle
- Control API ใช้ schema version 1 จาก `/health`; message มี `captureState` เช่น `complete`, `truncated`, `streamed`, `encoded`, `binary` ข้อมูลเก่าที่ไม่มีฟิลด์ไม่ถือเป็นหลักฐานว่า body ครบ
- Text editor ลงสีเฉพาะ 256K UTF-16 code units แรก แต่บันทึก body เต็มภายใต้ limit 8 MiB การ format JSON จำกัด output ตาม mock size เพื่อกันการขยายจาก nesting
- เมื่อ settings หรือ saved filters โหลดไม่ได้ แอปแจ้ง error และไม่ overwrite ไฟล์ที่มีปัญหาอัตโนมัติ ให้ตรวจข้อมูลก่อน reset
- การเปิดแอปครั้งแรกย้าย layout preferences เดิมมายัง settings.json ส่วนขนาด/ลำดับคอลัมน์และ divider จำผ่าน workspace preferences

Engine pin ไว้ที่ mitmproxy **12.2.3 macOS arm64** build script ตรวจ SHA-256 และ code signature ต้นฉบับ vendor และ dependency notices ต้องคงไว้เมื่อแจก ดู [Third-party notices](../THIRD_PARTY_NOTICES.md) และ [ENGINE_SOURCE.md](ENGINE_SOURCE.md) สำหรับ source/checksum และการ rebuild/เปลี่ยน engine ในสำเนาแอป

ขั้นตอน rebuild ไม่ใช่การรับรอง byte-identical build, legal clearance หรือ audit dependency native/Rust ครบทุกตัว โค้ด Reqnivo ใช้ [MIT License](../LICENSE) ส่วน dependency ใช้ license ของแต่ละโครงการ ดู [Public release review](PUBLIC_RELEASE_REVIEW.md) สำหรับรายการที่ยังต้องยืนยันก่อนเผยแพร่
