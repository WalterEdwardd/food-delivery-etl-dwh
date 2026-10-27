# QuickBite Pipeline Monitoring & Observability (Power BI)

This directory contains all data assets, Tabular models (TMDL/BIM), themes, and technical documentation for the **Power BI Pipeline Monitoring & Observability Dashboard** of the QuickBite Data Platform.

---

## 1. Directory Structure

```text
powerbi/pipeline_monitoring/
│
├── Pipeline_Monitoring.pbix     <-- Power BI Desktop report for ETL observability
├── quickbite_theme_platinum_silver.json <-- Official Platinum Silver Luxury Theme
├── tmdl/                        <-- Source-controlled Tabular Model Definition Language (PBIP)
│   ├── database.tmdl
│   ├── model.tmdl
│   ├── relationships.tmdl
│   ├── cultures/
│   │   └── en-US.tmdl
│   └── tables/
│       ├── _Measures.tmdl
│       ├── Batch.tmdl
│       ├── Step.tmdl
│       ├── Error.tmdl
│       ├── Warning.tmdl
│       ├── Reconciliation.tmdl
│       └── Audit.tmdl
│
├── DASHBOARD_GUIDE.md           <-- Comprehensive dashboard specifications and ops playbooks
├── data_dictionary.md           <-- Detailed data dictionary (Tables, columns, DAX measures, relationships)
└── README.md                    <-- This technical documentation
```

---

## 2. Technical Documentation & References

* 📘 **Dashboard Technical Specification & User Guide**: [DASHBOARD_GUIDE.md](DASHBOARD_GUIDE.md)  
  * Detailed architectural and visual breakdown for all 4 dashboard pages (**Page 1**: Executive Health & SLA Overview, **Page 2**: Step Performance & Bottlenecks, **Page 3**: Data Quality & Errors, **Page 4**: Layer Reconciliation & Audit).
  * Specifications for the 5-KPI card headers (Callout value + dynamic subtext), DAX measures, dynamic conditional formatting, Bookmark navigators, and threshold matrices.
  * Deep-dive technical reconciliation equations (physical row differences vs. multi-column errors, absolute volume vs. percentage anomaly paradoxes, 3-layer balance equation `RAW ➔ ODS ➔ DWH` with SCD Type 2 expansion) and incident response on-call playbooks.
* 📖 **Full Data Dictionary**: [data_dictionary.md](data_dictionary.md)  
  * Detailed technical specifications for all 6 tables (`Batch`, `Step`, `Error`, `Warning`, `Reconciliation`, `Audit`).
  * Complete column catalogs, data types, nullability, and business definitions.
  * Semantic model relationships (5 tables connecting 1:N with `Batch`).
  * Clean catalog of 69 DAX measures organized into 6 standardized display folders.
* 📜 **SQL Semantic Views**: [`sql/database/11_control_monitoring_views.sql`](file:///c:/Users/PC/Downloads/food-delivery-etl-dwh/sql/database/11_control_monitoring_views.sql)
* 📘 **Operations Runbook**: [`docs/runbook/powerbi_pipeline_monitoring_dashboard.md`](file:///c:/Users/PC/Downloads/food-delivery-etl-dwh/docs/runbook/powerbi_pipeline_monitoring_dashboard.md)
