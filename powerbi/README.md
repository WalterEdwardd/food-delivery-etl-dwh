# Power BI Workspace - QuickBite Data Platform

This directory organizes all Power BI reports, data models, and documentation for the QuickBite Data Platform, structured by operational domain:

---

## Directory Structure

```text
powerbi/
│
├── pipeline_monitoring/             <-- Technical Observability & Pipeline Monitoring (Data Engineering & Ops)
│   ├── Pipeline_Monitoring.pbix     <-- Power BI Desktop report for ETL monitoring
│   ├── quickbite_theme_platinum_silver.json <-- Official Platinum Silver Luxury theme
│   ├── quickbite_dark_theme.json    <-- Dark mode theme
│   ├── data_dictionary.md           <-- Control & Data Quality data dictionary and DAX catalog
│   ├── DASHBOARD_GUIDE.md           <-- Comprehensive dashboard specifications and ops playbooks
│   ├── model.bim                    <-- Tabular Model definition (BIM format)
│   ├── README.md                    <-- Pipeline monitoring technical guide
│   └── tmdl/                        <-- Source-controlled Tabular Model Definition Language (PBIP)
│
├── business_analytics/              <-- Business Analytics & Commercial Reporting
│   └── DONE-RPC_18/                 <-- Reference datasets, template models, and specifications
│
└── assets/                          <-- Branding assets (QuickBite / GrabFood logos)
```

---

## Scope & Target Audience

| Criteria | `pipeline_monitoring/` (Current Focus) | `business_analytics/` (Commercial Domain) |
| :--- | :--- | :--- |
| **Target Audience** | Data Engineers, Platform Engineers, DevOps, SRE | Business Analysts, Product Managers, C-Level Leadership |
| **Core Objective** | Pipeline health, freshness SLA, step latency, quarantined DQ errors | GMV growth, order trends, delivery efficiency, partner performance |
| **Data Source** | Semantic monitoring schema (`control.*` semantic views) | Data Warehouse schema (`dwh.*` Star Schema) |
