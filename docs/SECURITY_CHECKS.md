# ระบบตรวจ security บน GitHub

## CI: build, test และตรวจแพ็กเกจ

ไฟล์ `.github/workflows/ci.yml` รันเมื่อ push เข้า `main` หรือ push tag `v*`, เปิดหรืออัปเดต PR
ที่เข้า `main` และสั่งเองผ่าน **Actions → CI → Run workflow** งาน build/test/package ใช้ macOS 15 arm64
run เก่าบน branch เดียวกันจะถูกยกเลิกเมื่อมี run ใหม่

| Job | สิ่งที่ตรวจ |
| --- | --- |
| `Build & Test` | `./scripts/swift.sh build`, ดาวน์โหลดและตรวจ checksum/signature ของ engine ด้วย `./scripts/fetch-engine.sh` แล้วรัน `./scripts/swift.sh test` ทั้งชุด รวม tests ที่เปิด engine จริง |
| `Engine Integration` | ดาวน์โหลด engine ที่ pin ไว้ ตรวจ checksum/signature แล้วรัน capture 100 requests, Map Local/breakpoints และ selective HTTPS decryption |
| `Package Verification` | หลังสองงานแรกผ่าน เฉพาะ push `main`/tag หรือสั่งเอง: ตรวจ source archives, build release `.app`, สร้าง ZIP แล้วแตกกลับเพื่อตรวจ signature, arm64, bundle metadata และไฟล์ legal/source |
| `Draft Release` | เฉพาะ push tag หลัง package ผ่าน: ตรวจ checksum ของ artifacts ที่ดาวน์โหลด แล้วสร้าง Draft Pre-release บน GitHub |

CI เก็บ stdout/stderr เป็น artifacts อายุ 7 วัน รวมถึงเมื่อ job ล้มเหลว
แพ็กเกจที่ตรวจผ่านอยู่ใน artifact `Proxiverse-macOS-arm64-<commit SHA>` อายุ 14 วัน
ประกอบด้วย ZIP และ `SHA256SUMS.txt` ดาวน์โหลดจากหน้า run แล้วแตก artifact ก่อนใช้
ตรวจ checksum ได้ด้วย `shasum -a 256 -c SHA256SUMS.txt` ในโฟลเดอร์ที่มี ZIP
การรันบน `main` หรือสั่งเองไม่สร้าง GitHub Release แพ็กเกจยังใช้ ad-hoc signing ตาม build script

### สร้าง Draft Release ด้วย tag

1. แก้ version/build number ใน `scripts/build-app.sh` และตรวจข้อความใน
   `docs/RELEASE_NOTES.md` ซึ่งใช้เป็นข้อความตั้งต้นของ release
2. Commit การเปลี่ยนแปลง รวมถึง workflow แล้ว push ขึ้น GitHub
3. สร้าง tag ใหม่บน commit ที่ต้องการแจก ชื่อ tag ต้องเป็น `v` ตามด้วย
   `CFBundleShortVersionString` เช่น version `0.0.5` ใช้ tag `v0.0.5`:

   ```sh
   git tag v0.0.5
   git push origin v0.0.5
   ```

4. ดู **Actions → CI** ของ tag นั้น ระบบรัน build/tests และ engine integration ใหม่
   จาก commit ของ tag หาก test ล้มเหลวหรือ version ไม่ตรง tag จะไม่สร้าง Draft
5. เมื่อผ่าน ไปที่ **Releases** จะพบ Draft ที่เลือก Pre-release ไว้ พร้อม app ZIP,
   `Proxiverse-engine-source-12.2.3.zip` และ `SHA256SUMS.txt` ที่ครอบคลุมทั้งสอง ZIP
   source ZIP รวม archives, notices และ helper scripts จาก commit ของ tag
   Release notes มีข้อความตั้งต้นและรายการเปลี่ยนแปลงที่ GitHub สร้างให้
6. ตรวจ notes และทดสอบไฟล์ดาวน์โหลด ก่อนกด Publish ด้วยตนเอง

ใช้ tag ใหม่สำหรับเวอร์ชันใหม่ Workflow ไม่แก้หรือเขียนทับ release ที่มีอยู่
ถ้า run ถูกสั่งซ้ำหลังสร้าง Draft สำเร็จ ขั้นสร้าง release จะล้มเหลวเพราะ release มีอยู่แล้ว
การสร้าง Draft ใช้ `GITHUB_TOKEN` พร้อม `contents: write` เฉพาะ job นี้ ไม่ต้องเพิ่ม PAT
Repository ต้องอนุญาตให้ workflow ใช้สิทธิ์ดังกล่าว
ปุ่ม Run workflow ใช้ตรวจ CI เท่านั้น ไม่สร้าง Draft แม้เลือก tag

`WorkspaceTests.testSetupStatusesReflectActualFileAndEngineState` ตรวจค่าเริ่มต้น localhost-only
และสถานะเมื่อเปิด/ปิด LAN โดย workflow ต้องรอ tests ผ่านก่อนสร้าง Draft

คำสั่งตรวจแพ็กเกจในเครื่อง:

```sh
python3 scripts/verify-engine-sources.py
./scripts/build-app.sh
./scripts/verify-app-package.sh
```

ผลอยู่ใน `dist/ci/` การตรวจนี้ไม่ยืนยัน Apple notarization, การเปิดครั้งแรกบน Mac
อีกเครื่อง หรือการทำงานบน macOS 14 ส่วน integration ใช้ fixture และ CA ชั่วคราว
ไม่เปลี่ยน system proxy หรือ trust store และไม่ได้ทดสอบ GUI/อุปกรณ์จริง
test ที่ต้องติดตั้ง CA บน Android emulator ยังต้อง opt-in แยกจาก CI
หาก Swift tests เดิมล้มเหลว CI จะรายงานล้มเหลวโดยไม่ข้าม test เหล่านั้น

## การตรวจอัตโนมัติ

ไฟล์ `.github/workflows/codeql.yml` ตั้งให้ CodeQL ตรวจเมื่อ push เข้า `main`,
เปิดหรืออัปเดต Pull Request ที่เข้า `main`, ทุกวันจันทร์เวลา 09:23 น. ประเทศไทย
และสั่งเองผ่าน **Actions → CodeQL → Run workflow** ได้
การรันตามรอบและปุ่มสั่งเองต้องมี workflow อยู่บน default branch ก่อน
เมื่อ push commit ใหม่ใน PR เดิม run ที่กำลังทำงานอยู่จะถูกยกเลิกเพื่อใช้ผลจาก commit ล่าสุด

- Swift: build ด้วย `./scripts/swift.sh build` บน macOS 15 แล้ววิเคราะห์โค้ดที่ build
- Python: วิเคราะห์ `Sources` และ `scripts` บน Linux โดยไม่รันสคริปต์
- Dependabot: ตรวจเวอร์ชัน Actions ที่ workflow ใช้ทุกสัปดาห์ และเปิด PR เสนอให้อัปเดต

Actions ใน CI และ CodeQL pin ด้วย full commit SHA เพื่อให้แต่ละ run ใช้โค้ดรุ่นที่ระบุแน่นอน

ระบบนี้ไม่ดาวน์โหลดหรือเปิดแอป mitmproxy และไม่วิเคราะห์ binary ใน `vendor` หรือ `dist`
การสแกนผ่านไม่ได้ยืนยันว่าแอปหรือ engine ปลอดช่องโหว่ทั้งหมด

## เปิดใช้งานบน repository

1. นำไฟล์ตั้งค่าเข้า default branch ของ GitHub repository (ปัจจุบันใช้ `main`)
2. ใน **Settings → Actions → General** อนุญาต GitHub Actions และ Actions ของ
   `actions/checkout` กับ `github/codeql-action` ตามนโยบาย repository
3. ใน **Settings → Code security** ตรวจว่า Code scanning ใช้ **Advanced setup**
   ผ่าน workflow นี้ หากเปิด CodeQL Default setup ไว้ ให้ปิดก่อนใช้ workflow นี้
4. รอ workflow แรก หรือสั่งผ่าน **Actions → CodeQL → Run workflow**
5. ตรวจว่า jobs `Analyze (swift)` และ `Analyze (python)` ผ่าน และดูผลที่
   **Security → Code scanning** การไม่พบ alert มีความหมายเมื่อ analysis สำเร็จแล้ว

Code scanning ใช้ได้ฟรีบน public repository ส่วน private/internal repository
ต้องมีแผนและสิทธิ์ GitHub Code Security ที่รองรับ อาจมีค่า Actions ตามแผนที่ใช้

## Secret scanning และการบังคับก่อน merge

Secret scanning และ Push protection เป็นการตั้งค่าบน GitHub แยกจาก workflow นี้
ให้ตรวจหรือเปิดใน **Settings → Secret Protection** ตามสิทธิ์และแผนที่รองรับ
เพื่อแจ้งเตือน secret ที่หลุดและบล็อกการ push secret ที่ตรวจพบ

หากต้องการบังคับตรวจให้ผ่านก่อน merge ให้รอการรันสำเร็จครั้งแรก แล้วเพิ่ม
`Build & Test`, `Engine Integration`, `Analyze (swift)` และ `Analyze (python)` เป็น required status checks
ใน ruleset หรือ branch protection ของ `main` ตามสิทธิ์และแผนที่รองรับ
ไม่ตั้ง `Package Verification` หรือ `Draft Release` เป็น required checks เพราะงานเหล่านี้ไม่รันบน PR
การบังคับให้ job ผ่านตรวจว่าการวิเคราะห์ทำงานสำเร็จ ส่วนการบล็อกตาม alert
ต้องตั้ง code scanning merge protection แยกตามความสามารถของแผน

เอกสารอ้างอิง:

- [CodeQL สำหรับภาษาที่ต้อง build](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/codeql-for-compiled-languages)
- [สิทธิ์ใช้งาน GitHub security](https://docs.github.com/en/code-security/getting-started/github-security-features)
- [Secret scanning](https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning)
