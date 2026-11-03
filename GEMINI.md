# Power BI Design System & Workflow Rules: QuickBite Platinum Silver Luxury

Khi hỗ trợ chuẩn hóa giao diện báo cáo Power BI Business Analytics (`powerbi/business_analytics/Grab_Food_Delivery.pbix`) theo ngôn ngữ thiết kế **"QuickBite Platinum Silver Luxury"** (đã áp dụng tại `powerbi/pipeline_monitoring/Pipeline_Monitoring.pbix` và `powerbi/pipeline_monitoring/quickbite_theme_platinum_silver.json`), luôn tuân thủ tuyệt đối các nguyên tắc bất di bất dịch sau đây cho **TẤT CẢ** các Visual:

---

## 1. NGUYÊN TẮC CỐT LÕI: "ĐỒNG NHẤT THẨM MỸ - LINH HOẠT TỶ LỆ (DESIGN DNA vs. CONTENT-ADAPTIVE SIZING)"

- **Đồng nhất 100% về Design DNA:**
  - Bảng màu (Color Palette)
  - Chất liệu khung thẻ (Background, Border, Corner Radius, Shadow, Accent Bar, Divider)
  - Font chữ (`Segoe UI` / `Segoe UI Semibold`)
  - Phân cấp màu sắc ngữ nghĩa (Semantic Status Colors)
- **Linh hoạt tỷ lệ theo mật độ nội dung (Content-Adaptive Sizing):**
  - **TUYỆT ĐỐI KHÔNG** bê nguyên cứng nhắc các thông số kích thước, cỡ chữ (`Font size`), tỷ lệ `Callout size`, hay `Padding` từ `Pipeline_Monitoring.pbix` (màn hình `1920x1080`, 5 cards) sang `Grab_Food_Delivery.pbix` (màn hình `1280x720`, 7 cards, mật độ thông tin dày hơn).
  - Mọi thông số về kích thước, tỷ lệ chia vùng, cỡ chữ và khoảng cách phải được tinh chỉnh linh hoạt dựa trên độ dài text, số lượng chỉ số và diện tích thực tế của từng Visual trên từng trang.

---

## 2. HỆ MÀU SẮC CHUẨN (PLATINUM SILVER & GRAB EMERALD PALETTE)

- **Nền trang (Canvas Background):** Xám bạc sáng `#F1F5F9` (Outspace: `#E2E8F0`, Transparency `0%`).
- **Nền Visual / Card (Surface Fill):** Trắng tinh khiết `#FFFFFF` (Transparency `0%`).
- **Viền & Đường phân cách (Border & Divider):** Xám mảnh `#E2E8F0` (`1px`).
- **Đổ bóng (Drop Shadow):** Màu Slate `#64748B` dịu nhẹ (`Outer` / `Bottom right` - Angle `90`, Blur `14px`, Distance `3px`, Spread `0px`, Transparency `86%`).
- **Bảng màu dữ liệu (Data Colors):**
  - **Primary / Thương hiệu:** `#009E46` (Grab Emerald Green) & `#00B14F`
  - **Secondary / Đối sánh:** `#0F2C67` (Executive Deep Navy)
  - **Auxiliary / Bổ trợ:** `#7C3AED` (Purple), `#0D9488` (Teal), `#64748B` (Slate)
- **Màu ngữ nghĩa (Semantic Status Colors):**
  - **Tích cực / Đạt chuẩn (Good):** `#009E46` (hoặc 🟢)
  - **Cảnh báo / Trung tính (Warning/Neutral):** `#FF8F00` (hoặc 🟡)
  - **Tiêu cực / Rủi ro (Bad/Critical):** `#C40C0C` (hoặc 🔴)

---

## 3. TIÊU CHUẨN CHUNG CHO TỪNG NHÓM VISUAL

### 3.1. Khung Visual chung (Charts, Tables, Matrices)
- **Surface:** Background `#FFFFFF`, Border `#E2E8F0`, bo góc `10px`, bật Drop Shadow nhẹ (`#64748B`, Blur `14px`, Distance `3px`, Transparency `86%`).
- **Typography:**
  - `Title`: Font `Segoe UI Semibold`, màu `#0F172A`.
  - `Subtitle`: Font `Segoe UI`, màu `#64748B`.

### 3.2. KPI Card (`Card (new)` / `cardVisual`)
- **Container ngoài (nếu gộp nhiều thẻ trong 1 container):** Tắt `Background`, `Border`, `Shadow` của Container ngoài; bật trên từng Card con bên trong.
- **Thẻ con (Individual Cards):**
  - Nền `#FFFFFF`, bo góc `10px` (`rectangleRoundedCurve: 10`), viền `#E2E8F0` (`1px`, Transparency `20%`), Shadow `Bottom right` (`#64748B`).
  - Thanh `Accent Bar` bên trái (`Left`), màu `#009E46`, dày `4px`.
- **Phần chính (Callout):**
  - `Label`: Nằm trên (`Above value`), font `Segoe UI Semibold`, màu `#64748B`.
  - `Value`: Font `Segoe UI Semibold`, màu `#0F172A`.
- **Phần phụ (Reference Labels):**
  - **TẮT** nền xám mặc định (`Background = Off`).
  - Ngăn cách bằng `Divider` màu `#E2E8F0` (`Ignore padding = On`).
  - Chữ `Title` màu `#64748B`, chữ `Value` màu `#334155` (hoặc màu ngữ nghĩa `#009E46` / `#FF8F00` / `#C40C0C`).
- **Cân chỉnh linh hoạt:** Tỷ lệ `Callout size`, `Font size`, `Padding`, `Space between cards` và bố cục Reference Labels (`Vertical`/`Horizontal`, `Tabular`/`Sentence`) được cân chỉnh vừa vặn theo số lượng thẻ và số dòng nội dung thực tế.

### 3.3. Bảng & Ma trận (`Table` / `tableEx` & `Matrix` / `pivotTable`)
- **Header cột (`columnHeaders`):** Nền xanh bạc hà nhạt `#ECFDF5`, chữ xanh đậm `#065F46`, font `Segoe UI Semibold`.
- **Dòng dữ liệu (`values` & `grid`):** Chữ `#1E293B`, nền dòng xen kẽ `#FFFFFF` và `#F8FAFC`, lưới ngang (`gridHorizontal`) màu `#F1F5F9`, viền ngoài (`outlineColor`) `#E2E8F0`.

### 3.4. Biểu đồ (`Bar`, `Column`, `Line`, `Combo`, `Donut`, `Gauge`)
- Ưu tiên tối giản, trục tọa độ màu `#64748B`, đường lưới mờ `#F1F5F9` / `#E2E8F0`.
- Sử dụng đúng thứ tự màu `Data Colors` và màu ngữ nghĩa của Theme (`quickbite_theme_platinum_silver.json`).

---

## 4. QUY TRÌNH PHỐI HỢP (COLLABORATION WORKFLOW)

- **Không tự ý áp đặt hàng loạt** khi chưa thống nhất.
- Đi từng Visual / từng khu vực một: phân tích mật độ nội dung và diện tích thực tế → thảo luận phương án bố cục & thông số tối ưu cho Visual đó → nhận sự đồng ý của người dùng rồi mới thực hiện.
