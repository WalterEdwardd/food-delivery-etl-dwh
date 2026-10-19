# Food Delivery SSIS Packages (Enterprise Reference Architecture)

## Overview

This directory contains the **SQL Server Integration Services (SSIS)** solution developed in **Visual Studio (SQL Server Data Tools - SSDT)** for the Food Delivery Data Warehouse.

It models the **RAW -> ODS** data transformation, validation, and upsert pipeline using graphical SSIS Data Flow Tasks and Control Flow containers.

---

## Architecture Role: Reference Implementation vs. Production Pipeline

| Attribute | SSIS Implementation (`ssis/`) | Production Automated Pipeline (`run_monthly_pipeline.py`) |
| :--- | :--- | :--- |
| **Engine** | Microsoft SQL Server Integration Services (SSIS) | Python CLI + Native T-SQL Stored Procedures |
| **Role** | **Enterprise Reference Architecture** | **Active Production Pipeline** |
| **Requirements** | Visual Studio SSDT, SQL Server Standard/Enterprise, SSIS Service | Lightweight, Python 3.10+, any SQL Server edition (incl. Express) |
| **Execution** | Visual Studio GUI or `dtexec` via SSISDB / SQL Server Agent | `python run_monthly_pipeline.py --month <YYYY_MM>` |
| **Throughput** | Visual debugging / manual batch runs | ~16–30s per monthly batch (~500k+ rows) |

---

## Package Catalog

| Package | Name | Description |
| :---: | :--- | :--- |
| **01** | `01_Pipeline_Orchestrator.dtsx` | Master orchestrator controlling the execution sequence of packages 02 to 09 with precedence constraints. |
| **02** | `02_Load_DeliveryPartner.dtsx` | Cleanses driver demographic and onboarding data from `raw_delivery_partner` to `ods_delivery_partner`. |
| **03** | `03_Load_Restaurant.dtsx` | Cleanses restaurant profiles, cuisine categories, and locations from `raw_restaurant` to `ods_restaurant`. |
| **04** | `04_Load_MenuItem.dtsx` | Validates menu item pricing and category taxonomy from `raw_menu_item` to `ods_menu_item`. |
| **05** | `05_Load_Customer.dtsx` | Cleanses customer profiles and registration channels from `raw_customer` to `ods_customer`. |
| **06** | `06_Load_Order.dtsx` | Validates transaction amounts, payment methods, and timestamps from `raw_order` to `ods_order`. |
| **07** | `07_Load_OrderItem.dtsx` | Reconciles line items, item discounts, and quantities from `raw_order_item` to `ods_order_item`. |
| **08** | `08_Load_DeliveryPerformance.dtsx` | Transforms delivery trip timings, prep times, and distances from `raw_delivery_performance` to `ods_delivery_performance`. |
| **09** | `09_Load_Rating.dtsx` | Processes customer feedback ratings and reviews from `raw_rating` to `ods_rating`. |

---

## How to Open in Visual Studio

1. Open Visual Studio with **SQL Server Data Tools (SSDT)** or the **SQL Server Integration Services Projects** extension installed.
2. Open solution file: `ssis/FoodDeliveryETL/FoodDeliveryETL.sln`.
3. Configure the Project Connection Manager `CM_FoodDeliveryDW` to point to your target SQL Server instance.
