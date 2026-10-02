/*
============================================================
PART 14 - DATA MART LAYER (RETIRED)
Database : FoodDeliveryDW
Platform : Microsoft SQL Server

ARCHITECTURE DECISION:
    The physical Data Mart layer is retired.
    The enterprise architecture strictly follows:
        RAW -> ODS -> DWH (Single Source of Truth) -> Power BI
    Power BI reports directly query the DWH layer (Physical Tables
    & Serving Views) to ensure data consistency, eliminate latency,
    and optimize storage resources.
============================================================
*/
