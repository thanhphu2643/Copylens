# Copylens

Trích xuất text từ bất kỳ vùng nào trên màn hình macOS rồi copy vào clipboard, giống Text Extractor của PowerToys.

Nhấn **⌘⇧T**, kéo chuột khoanh vùng, thả chuột là text đã nằm trong clipboard. **Esc** hoặc chuột phải để huỷ.

## Build và chạy

Cần macOS 14+, Xcode và Rust.

```bash
./build.sh
open build/Copylens.app
```

Đóng gói DMG: `./dmg.sh` (kết quả ở `build/Copylens-<version>.dmg`).

Lần chụp đầu tiên macOS sẽ hỏi quyền **Screen Recording**. Cấp quyền trong System Settings rồi mở lại app.

Khi nằm trong Applications, app tự đăng ký chạy khi đăng nhập ở lần mở đầu tiên. Có thể tắt trong cửa sổ Copylens. Mở cửa sổ từ icon trên menu bar hoặc mở lại app từ Applications.

## Cấu trúc

| Phần | Việc |
| --- | --- |
| `Sources/Copylens` (Swift) | Menu bar, hotkey, overlay khoanh vùng, ScreenCaptureKit, Vision OCR, clipboard |
| `scripts/make-icon.swift` | Vẽ `Resources/AppIcon.icns` |
| `core` (Rust) | Engine OCR dự phòng PP-OCRv5 trên ONNX Runtime (CPU), sắp fragment OCR thành dòng và đoạn, chuẩn hoá NFC |
| `Sources/CTextCore` | Header C nối Swift với Rust |

OCR chạy hoàn toàn trên máy, với hai engine chạy đua:

- **Vision** chạy trước: khoảng 0,2 giây, đọc được cả tiếng Anh và tiếng Việt có dấu.
- **PP-OCRv5** vào cuộc nếu sau 0,7 giây Vision chưa xong hoặc báo lỗi, vì thỉnh thoảng macOS biên dịch lại model của Vision (`ANECompilerService`, khoảng 33 giây). Engine này trả kết quả trong khoảng 1,5 giây tính từ lúc chụp và chỉ đọc được tiếng Anh/Latin, không có dấu tiếng Việt. Thông báo sau khi copy sẽ ghi rõ khi app dùng chế độ này.

## Kiểm thử

```bash
cargo test --manifest-path core/Cargo.toml
.build/release/Copylens --ocr anh.png        # OCR bằng Vision, không cần UI hay quyền
build/Copylens.app/Contents/MacOS/Copylens --ocr-fast anh.png   # OCR bằng PP-OCRv5
```

## Giới hạn

- ⌘⇧T là phím toàn hệ thống nên trong lúc app chạy, phím này không còn "mở lại tab vừa đóng" trong trình duyệt. Đổi phím ở `Sources/Copylens/HotKey.swift`.
- Lần chụp trúng lúc Vision đang biên dịch lại sẽ không có dấu tiếng Việt. Chụp lại sau khoảng 30 giây là có dấu.
- Văn bản nhiều cột sẽ bị ghép theo hàng ngang. Hãy khoanh từng cột.

## Thành phần bên thứ ba

- [ONNX Runtime](https://github.com/microsoft/onnxruntime) (MIT): `fetch-onnxruntime.sh` tải bản chính thức và kiểm tra SHA-256.
- Model PP-OCRv5 của [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) (Apache-2.0), bản chuyển sang ONNX từ [monkt/paddleocr-onnx](https://huggingface.co/monkt/paddleocr-onnx), nằm trong `core/models`.
