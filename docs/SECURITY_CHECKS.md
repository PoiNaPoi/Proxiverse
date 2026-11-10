# ระบบตรวจ security บน GitHub

## การตรวจอัตโนมัติ

ไฟล์ `.github/workflows/codeql.yml` ตั้งให้ CodeQL ตรวจเมื่อ push เข้า `main`,
เปิดหรืออัปเดต Pull Request ที่เข้า `main`, ทุกวันจันทร์เวลา 09:23 น. ประเทศไทย
และสั่งเองผ่าน **Actions → CodeQL → Run workflow** ได้
การรันตามรอบและปุ่มสั่งเองต้องมี workflow อยู่บน default branch ก่อน

- Swift: build ด้วย `./scripts/swift.sh build` บน macOS 15 แล้ววิเคราะห์โค้ดที่ build
- Python: วิเคราะห์ `Sources` และ `scripts` บน Linux โดยไม่รันสคริปต์
- Dependabot: ตรวจเวอร์ชัน Actions ที่ workflow ใช้ทุกสัปดาห์ และเปิด PR เสนอให้อัปเดต

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
`Analyze (swift)` และ `Analyze (python)` เป็น required status checks
ใน ruleset หรือ branch protection ของ `main` ตามสิทธิ์และแผนที่รองรับ
การบังคับให้ job ผ่านตรวจว่าการวิเคราะห์ทำงานสำเร็จ ส่วนการบล็อกตาม alert
ต้องตั้ง code scanning merge protection แยกตามความสามารถของแผน

เอกสารอ้างอิง:

- [CodeQL สำหรับภาษาที่ต้อง build](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/manage-your-configuration/codeql-for-compiled-languages)
- [สิทธิ์ใช้งาน GitHub security](https://docs.github.com/en/code-security/getting-started/github-security-features)
- [Secret scanning](https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning)
