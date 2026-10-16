# QuickBite Pipeline Monitoring & Observability (Power BI)

Thư mục này lưu trữ toàn bộ tài nguyên, định nghĩa mô hình (TMDL/BIM) và tài liệu phục vụ **Power BI Pipeline Monitoring & Observability Dashboard** của dự án QuickBite Data Platform.

---

## 1. Cấu Trúc Thư Mục

```text
powerbi/pipeline_monitoring/
│
├── Pipeline_Monitoring.pbix     <-- File Power BI Desktop chính (Lưu từ Power BI Desktop)
├── model.bim                    <-- File định nghĩa toàn bộ mô hình (BIM format)
│
├── tmdl/                        <-- Định nghĩa Tabular Model dạng văn bản (TMDL / PBIP format)
│   ├── database.tmdl
│   ├── model.tmdl
│   ├── relationships.tmdl
│   ├── _Measures.tmdl
│   ├── Batch.tmdl
│   ├── Step.tmdl
│   ├── Error.tmdl
│   ├── Warning.tmdl
│   ├── Reconciliation.tmdl
│   └── Audit.tmdl
│
├── data_dictionary.md           <-- Từ điển dữ liệu chi tiết (Mô tả bảng, cột, kiểu dữ liệu, DAX, relations)
└── README.md                    <-- Hướng dẫn thư mục này
```

---

## 2. Hướng Dẫn Lưu File Power BI Desktop (`.pbix`)

Vì bạn đang mở file **Power BI Desktop ("Untitled - Power BI Desktop")** đã được đồng bộ toàn bộ bảng và measures:

1. Chuyển sang cửa sổ **Power BI Desktop**.
2. Nhấn tổ hợp phím **`Ctrl + S`** (hoặc chọn menu **File** ➔ **Save As**).
3. Điều hướng đến thư mục:
   ```text
   c:\Users\PC\Downloads\food-delivery-etl-dwh\powerbi\pipeline_monitoring\
   ```
4. Đặt tên file là: **`Pipeline_Monitoring.pbix`** và nhấn **Save**.

Sau khi lưu, file `.pbix` sẽ nằm trực tiếp trong thư mục này, kết hợp cùng các file định nghĩa mô hình TMDL / BIM đã được xuất tự động.

---

## 3. Tài Liệu Tham Khảo Nhanh

* 📖 **Data Dictionary Đầy Đủ**: [data_dictionary.md](data_dictionary.md)  
  * Mô tả chi tiết 6 bảng dữ liệu (`Batch`, `Step`, `Error`, `Warning`, `Reconciliation`, `Audit`).
  * Danh sách toàn bộ các cột, kiểu dữ liệu, nullability và ý nghĩa nghiệp vụ.
  * 4 Mối quan hệ trong mô hình.
  * 14 Công thức DAX chuẩn phân theo 4 nhóm.
* 📜 **SQL Semantic Views**: [`sql/database/11_control_monitoring_views.sql`](file:///c:/Users/PC/Downloads/food-delivery-etl-dwh/sql/database/11_control_monitoring_views.sql)
* 📘 **Vận Hành & Playbook Giám Sát**: [`docs/runbook/powerbi_pipeline_monitoring_dashboard.md`](file:///c:/Users/PC/Downloads/food-delivery-etl-dwh/docs/runbook/powerbi_pipeline_monitoring_dashboard.md)
