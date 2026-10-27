# 🔐 GITHUB CƠ BẢN — HARDWARE SECURITY ACCELERATOR

**RTL • Vivado • XSim • Sơ đồ thiết kế**

🎯 **Mục tiêu:** Lưu trữ code, chia sẻ sơ đồ và quản lý phiên bản trong nhóm.

## 🟢 1. Tải code lần đầu — CLONE

```bash
git clone https://github.com/ORG/hardware-security-accelerator.git
cd hardware-security-accelerator
git status
```

- `clone`: Tải repository về máy.
- `cd`: Vào thư mục project.
- `status`: Kiểm tra trạng thái file.

📌 Chỉ cần clone một lần cho mỗi bản sao repository.

## 🔵 2. Cập nhật code — PULL

```bash
git switch main
git pull --ff-only origin main
```

- `switch main`: Chuyển sang nhánh chính.
- `pull`: Lấy cập nhật mới từ GitHub.

⚠️ Kiểm tra code đang sửa trước khi cập nhật. Nếu đang làm trên nhánh riêng, hãy cập nhật đúng nhánh.

## 🟠 3. Đẩy code lên GitHub — ADD → COMMIT → PUSH

```bash
git status
git add rtl/ tb/
git commit -m "Add RTL and testbench"
git push
```

- `add`: Chọn file cần lưu.
- `commit`: Tạo phiên bản trên máy.
- `push`: Đẩy commit lên GitHub.

📌 Nếu tạo nhánh mới lần đầu:

```bash
git push -u origin feature/keccak-core
```

## 🟣 4. Tạo nhánh riêng — BRANCH

```bash
git switch main
git pull --ff-only origin main
git switch -c feature/keccak-core
```

Làm việc trên nhánh riêng để tránh ảnh hưởng code chung.

Khi hoàn thành:

1. Commit và push nhánh.
2. Tạo **Pull Request (PR)** trên GitHub.
3. Review code trước khi gộp vào `main`.

## 🖼️ 5. Lưu sơ đồ và tài liệu — DOCS



Lưu các file như `.drawio`, `.png`, `.svg`, `.pdf`, `.docx`.

```bash
mkdir docs
git add docs/
git commit -m "docs: add design diagrams"
git push
```

💡 Có thể tải file trực tiếp bằng GitHub → **Add file → Upload files**.

## 📘 6. README.md — Giới thiệu dự án

README nên có:

- 🎯 Mục tiêu thiết kế.
- 📂 Cấu trúc thư mục.
- ⚙️ Công cụ Vivado / XSim.
- 🧪 Hướng dẫn chạy mô phỏng.
- 👥 Thành viên và module phụ trách.

GitHub hỗ trợ tiêu đề, **in đậm**, danh sách, bảng, ảnh và khối code bằng Markdown.

## 🛠️ 7. Lệnh hữu ích

| Lệnh | Chức năng |
|---|---|
| `git status` | Kiểm tra trạng thái |
| `git diff` | Xem dòng code đã sửa |
| `git log --oneline -5` | Xem 5 commit gần nhất |
| `git branch -a` | Xem các nhánh |
| `git remote -v` | Xem địa chỉ repository |
| `git fetch origin` | Lấy thông tin mới từ GitHub |

## ⚙️ 8. Lưu ý khi dùng Vivado

**Nên lưu:** `.v`, `.sv`, `.vh`, `.xdc`, `.tcl`, testbench, file IP cần thiết và tài liệu.

**Thường bỏ qua:** file build, cache và waveform database dung lượng lớn.

Ví dụ `.gitignore`:

```gitignore
.Xil/
*.cache/
*.runs/
*.sim/
*.wdb
*.jou
```

⚠️ Kiểm tra `.xci` và `.bd` trước khi bỏ qua vì chúng có thể cần để tái tạo project.

---

## 🚀 GHI NHỚ

- 📥 **CLONE** = Tải lần đầu
- 🔄 **PULL** = Lấy cập nhật
- ☑️ **ADD** = Chọn file
- 💾 **COMMIT** = Lưu phiên bản trên máy
- ☁️ **PUSH** = Đẩy lên GitHub
- 🌿 **BRANCH** = Làm việc riêng
- 🔍 **PULL REQUEST** = Review code trước khi gộp
