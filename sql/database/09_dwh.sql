/*
============================================================
PART 13 - DWH LAYER
Database : FoodDeliveryDW
Schema   : dwh
Platform : Microsoft SQL Server

Purpose:
    Create Dimensional Data Warehouse tables.

Architecture:
    RAW
      ↓
    ODS
      ↓
    DWH (Single Source of Truth)
      ↓
    Power BI Reporting / Serving Layer (Direct Connect)

DWH responsibilities:
    - Dimensional modeling (Star Schema)
    - Surrogate Keys for join performance
    - Business key preservation
    - Conformed Dimensions
    - Fact measurements across core business processes
    - Preserve audit and lineage metadata (batch_id, load_timestamp)

IMPORTANT:
    DWH is the Single Source of Truth for Power BI reporting.
    No separate physical Data Mart layer is required.
============================================================
*/

USE FoodDeliveryDW;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO


/* =========================================================
   1. CREATE DWH SCHEMA & DROP EXISTING TABLES
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.schemas
    WHERE name = 'dwh'
)
BEGIN
    EXEC('CREATE SCHEMA dwh');
END;
GO

/* Drop existing tables in dependency order (Facts -> Core Dims -> Date/Time -> Lookup Dims) */
DROP TABLE IF EXISTS dwh.fact_review_aspect;
DROP TABLE IF EXISTS dwh.fact_rating;
DROP TABLE IF EXISTS dwh.fact_delivery_performance;
DROP TABLE IF EXISTS dwh.fact_order_item;
DROP TABLE IF EXISTS dwh.fact_order;

DROP TABLE IF EXISTS dwh.dim_menu_item;
DROP TABLE IF EXISTS dwh.dim_customer;
DROP TABLE IF EXISTS dwh.dim_restaurant;
DROP TABLE IF EXISTS dwh.dim_delivery_partner;

DROP TABLE IF EXISTS dwh.dim_time;
DROP TABLE IF EXISTS dwh.dim_date;

DROP TABLE IF EXISTS dwh.dim_aspect;
DROP TABLE IF EXISTS dwh.dim_sentiment_type;
DROP TABLE IF EXISTS dwh.dim_rating_type;
DROP TABLE IF EXISTS dwh.dim_life_cycles;
GO


/* =========================================================
   2. LOOKUP / CLASSIFICATION DIMENSIONS
   ========================================================= */

/* 2.1 DWH DIM LIFE CYCLES */
CREATE TABLE dwh.dim_life_cycles
(
    lc_id        TINYINT       NOT NULL,
    life_cycle   VARCHAR(50)   NOT NULL,
    description  VARCHAR(255)  NOT NULL,

    CONSTRAINT PK_dim_life_cycles
        PRIMARY KEY CLUSTERED (lc_id)
);
GO


/* 2.2 DWH DIM RATING TYPE */
CREATE TABLE dwh.dim_rating_type
(
    rating_type_id       TINYINT              NOT NULL,
    rating_type          VARCHAR(50)          NOT NULL,
    min_score            DECIMAL(3,2)         NOT NULL,
    max_score            DECIMAL(3,2)         NOT NULL,

    CONSTRAINT PK_dim_rating_type
        PRIMARY KEY CLUSTERED (rating_type_id)
);
GO


/* 2.3 DWH DIM SENTIMENT TYPE */
CREATE TABLE dwh.dim_sentiment_type
(
    sentiment_type_id    TINYINT              NOT NULL,
    sentiment_type       VARCHAR(50)          NOT NULL,
    min_score            DECIMAL(5,4)         NOT NULL,
    max_score            DECIMAL(5,4)         NOT NULL,

    CONSTRAINT PK_dim_sentiment_type
        PRIMARY KEY CLUSTERED (sentiment_type_id)
);
GO


/* 2.4 DWH DIM ASPECT */
CREATE TABLE dwh.dim_aspect
(
    aspect_id            TINYINT              NOT NULL,
    aspect_name          VARCHAR(50)          NOT NULL,
    aspect_description   VARCHAR(200)         NULL,

    CONSTRAINT PK_dim_aspect
        PRIMARY KEY CLUSTERED (aspect_id)
);
GO


/* =========================================================
   3. DATE & TIME DIMENSIONS
   ========================================================= */

/* 3.1 DWH DIM DATE */
CREATE TABLE dwh.dim_date
(
    date_key                INT           NOT NULL,
    full_date               DATE          NOT NULL,
    year                    SMALLINT      NOT NULL,
    quarter                 TINYINT       NOT NULL,
    quarter_name            VARCHAR(10)   NOT NULL,
    month                   TINYINT       NOT NULL,
    month_name              VARCHAR(20)   NOT NULL,
    month_short             VARCHAR(3)    NOT NULL,
    year_month              VARCHAR(7)    NOT NULL,
    week_of_year            TINYINT       NOT NULL,
    day_of_month            TINYINT       NOT NULL,
    day_of_week             TINYINT       NOT NULL,
    day_name                VARCHAR(20)   NOT NULL,
    day_short               VARCHAR(3)    NOT NULL,
    is_weekend              BIT           NOT NULL,

    fiscal_year             SMALLINT      NOT NULL,
    fiscal_quarter          VARCHAR(10)   NOT NULL,
    fiscal_quarter_number   TINYINT       NOT NULL,
    fiscal_month            VARCHAR(20)   NOT NULL,
    fiscal_month_number     TINYINT       NOT NULL,

    period                  VARCHAR(50)   NOT NULL,
    period_id               TINYINT       NOT NULL,

    CONSTRAINT PK_dim_date
        PRIMARY KEY CLUSTERED (date_key),

    CONSTRAINT UQ_dim_date_full_date
        UNIQUE (full_date)
);
GO


/* 3.2 DWH DIM TIME */
CREATE TABLE dwh.dim_time
(
    time_key        INT           NOT NULL,
    time_value      TIME(0)       NULL,
    hour            TINYINT       NOT NULL,
    minute          TINYINT       NOT NULL,
    hour_12         TINYINT       NOT NULL,
    am_pm           VARCHAR(2)    NOT NULL,
    time_display    VARCHAR(8)    NOT NULL,

    time_group      VARCHAR(50)   NOT NULL,
    time_group_id   TINYINT       NOT NULL,
    is_peak_hour    BIT           NOT NULL,

    CONSTRAINT PK_dim_time
        PRIMARY KEY CLUSTERED (time_key),

    CONSTRAINT UQ_dim_time_time_value
        UNIQUE (time_value)
);
GO


/* =========================================================
   4. ENTITY / CORE DIMENSIONS
   ========================================================= */

/* 4.1 DWH DIM CUSTOMER (Hybrid SCD Type 1 & 2) */
CREATE TABLE dwh.dim_customer
(
    customer_key            BIGINT IDENTITY(1,1) NOT NULL,
    customer_id             VARCHAR(50)          NOT NULL,
    signup_date             DATE                 NULL,
    city                    VARCHAR(100)         NULL, -- SCD Type 2
    acquisition_channel     VARCHAR(100)         NULL,

    last_active             DATE                 NULL, -- Last transaction date (from fact_order)
    life_cycle_id           TINYINT              NULL, -- Transaction lifecycle at last order (1: New, 2: Retained, 3: Reactivated)

    /* SCD Type 2 Timeline Metadata (Initial record valid_from initialized to signup_date; Unknown member key=-1 is 1900-01-01) */
    valid_from              DATE                 NOT NULL
        CONSTRAINT DF_dim_customer_valid_from DEFAULT '1900-01-01',
    valid_to                DATE                 NOT NULL
        CONSTRAINT DF_dim_customer_valid_to   DEFAULT '9999-12-31',
    is_current              BIT                  NOT NULL
        CONSTRAINT DF_dim_customer_is_current DEFAULT 1,

    batch_id                BIGINT               NOT NULL,
    load_timestamp          DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_customer_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_customer
        PRIMARY KEY CLUSTERED (customer_key),

    CONSTRAINT UQ_dim_customer_scd2
        UNIQUE (customer_id, valid_from),

    CONSTRAINT FK_dim_customer_life_cycle
        FOREIGN KEY (life_cycle_id) REFERENCES dwh.dim_life_cycles(lc_id)
);
GO


/* 4.2 DWH DIM RESTAURANT (Hybrid SCD Type 1 & 2) */
CREATE TABLE dwh.dim_restaurant
(
    restaurant_key          BIGINT IDENTITY(1,1) NOT NULL,
    restaurant_id           VARCHAR(50)          NOT NULL,
    onboard_date            DATE                 NULL,
    restaurant_name         VARCHAR(200)         NULL, -- SCD Type 2
    city                    VARCHAR(100)         NULL, -- SCD Type 2
    cuisine_type            VARCHAR(100)         NULL, -- SCD Type 2
    partner_type            VARCHAR(100)         NULL, -- SCD Type 2
    avg_prep_time_min       VARCHAR(50)          NULL,
    is_active               BIT                  NULL, -- SCD Type 2

    min_prep_min            INT                  NULL,
    max_prep_min            INT                  NULL,
    prep_time_group         VARCHAR(50)          NULL,
    prep_time_index         TINYINT              NULL,
    last_active             DATE                 NULL, -- Last transaction date (from fact_order)
    life_cycle_id           TINYINT              NULL, -- Transaction lifecycle at last order (1: New, 2: Retained, 3: Reactivated)

    /* SCD Type 2 Timeline Metadata (Initial record valid_from initialized to onboard_date; Unknown member key=-1 is 1900-01-01) */
    valid_from              DATE                 NOT NULL
        CONSTRAINT DF_dim_restaurant_valid_from DEFAULT '1900-01-01',
    valid_to                DATE                 NOT NULL
        CONSTRAINT DF_dim_restaurant_valid_to   DEFAULT '9999-12-31',
    is_current              BIT                  NOT NULL
        CONSTRAINT DF_dim_restaurant_is_current DEFAULT 1,

    batch_id                BIGINT               NOT NULL,
    load_timestamp          DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_restaurant_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_restaurant
        PRIMARY KEY CLUSTERED (restaurant_key),

    CONSTRAINT UQ_dim_restaurant_scd2
        UNIQUE (restaurant_id, valid_from),

    CONSTRAINT FK_dim_restaurant_life_cycle
        FOREIGN KEY (life_cycle_id) REFERENCES dwh.dim_life_cycles(lc_id)
);
GO


/* 4.3 DWH DIM DELIVERY PARTNER (Hybrid SCD Type 1 & 2) */
CREATE TABLE dwh.dim_delivery_partner
(
    delivery_partner_key    BIGINT IDENTITY(1,1) NOT NULL,
    delivery_partner_id     VARCHAR(50)          NOT NULL,
    onboard_date            DATE                 NULL,
    partner_name            VARCHAR(200)         NULL, -- SCD Type 2
    city                    VARCHAR(100)         NULL, -- SCD Type 2
    vehicle_type            VARCHAR(100)         NULL, -- SCD Type 2
    employment_type         VARCHAR(100)         NULL, -- SCD Type 2
    avg_rating              DECIMAL(5,2)         NULL,
    is_active               BIT                  NULL, -- SCD Type 2

    last_active             DATE                 NULL, -- Last transaction date (from fact_order)
    life_cycle_id           TINYINT              NULL, -- Transaction lifecycle at last order (1: New, 2: Retained, 3: Reactivated)
    rating_type_id          TINYINT              NULL,
    rating_type             VARCHAR(50)          NULL,

    /* SCD Type 2 Timeline Metadata (Initial record valid_from initialized to onboard_date; Unknown member key=-1 is 1900-01-01) */
    valid_from              DATE                 NOT NULL
        CONSTRAINT DF_dim_delivery_partner_valid_from DEFAULT '1900-01-01',
    valid_to                DATE                 NOT NULL
        CONSTRAINT DF_dim_delivery_partner_valid_to   DEFAULT '9999-12-31',
    is_current              BIT                  NOT NULL
        CONSTRAINT DF_dim_delivery_partner_is_current DEFAULT 1,

    batch_id                BIGINT               NOT NULL,
    load_timestamp          DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_delivery_partner_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_delivery_partner
        PRIMARY KEY CLUSTERED (delivery_partner_key),

    CONSTRAINT UQ_dim_delivery_partner_scd2
        UNIQUE (delivery_partner_id, valid_from),

    CONSTRAINT FK_dim_delivery_partner_life_cycle
        FOREIGN KEY (life_cycle_id) REFERENCES dwh.dim_life_cycles(lc_id)
);
GO


/* 4.4 DWH DIM MENU ITEM */
CREATE TABLE dwh.dim_menu_item
(
    menu_item_key        BIGINT IDENTITY(1,1) NOT NULL,
    menu_item_id         VARCHAR(50)          NOT NULL,
    restaurant_key       BIGINT               NULL,
    item_name            VARCHAR(200)         NULL,
    category             VARCHAR(100)         NULL,
    is_veg               BIT                  NULL,
    price                DECIMAL(18,2)        NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_menu_item_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_menu_item
        PRIMARY KEY CLUSTERED (menu_item_key),

    CONSTRAINT UQ_dim_menu_item_id
        UNIQUE (menu_item_id),

    CONSTRAINT FK_dim_menu_item_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dwh.dim_restaurant(restaurant_key)
);
GO


/* =========================================================
   5. FACT TABLES
   ========================================================= */

/* 5.1 DWH FACT ORDER */
CREATE TABLE dwh.fact_order
(
    order_key            BIGINT IDENTITY(1,1) NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    order_date_key       INT                  NOT NULL,
    order_time_key       INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,
    delivery_partner_key BIGINT               NOT NULL,

    subtotal_amount      DECIMAL(18,2)        NULL,
    discount_amount      DECIMAL(18,2)        NULL,
    delivery_fee         DECIMAL(18,2)        NULL,
    total_amount         DECIMAL(18,2)        NULL,
    net_order_value      DECIMAL(18,2)        NULL,

    is_cod               BIT                  NULL,
    is_cancelled         BIT                  NULL,

    cust_lc_id           TINYINT              NULL,
    rest_lc_id           TINYINT              NULL,
    driver_lc_id         TINYINT              NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_order_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_order
        PRIMARY KEY NONCLUSTERED (order_key),

    CONSTRAINT UQ_fact_order_order_id
        UNIQUE NONCLUSTERED (order_id)
);
GO

/* Clustered Columnstore Index with Date Ordering for Vectorized Analytics & Segment Elimination */
CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_order
    ON dwh.fact_order
    ORDER (order_date_key);
GO


/* 5.2 DWH FACT ORDER ITEM */
CREATE TABLE dwh.fact_order_item
(
    order_item_key       BIGINT IDENTITY(1,1) NOT NULL,
    order_item_id        VARCHAR(50)          NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    order_date_key       INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,
    menu_item_key        BIGINT               NOT NULL,

    quantity             INT                  NULL,
    unit_price           DECIMAL(18,2)        NULL,
    gross_line_total     DECIMAL(18,2)        NULL,
    item_discount        DECIMAL(18,2)        NULL,
    net_line_total       DECIMAL(18,2)        NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_order_item_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_order_item
        PRIMARY KEY NONCLUSTERED (order_item_key),

    CONSTRAINT UQ_fact_order_item_item_id
        UNIQUE NONCLUSTERED (order_item_id)
);
GO

/* Clustered Columnstore Index with Date Ordering for Vectorized Analytics */
CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_order_item
    ON dwh.fact_order_item
    ORDER (order_date_key);
GO


/* 5.3 DWH FACT DELIVERY PERFORMANCE */
CREATE TABLE dwh.fact_delivery_performance
(
    delivery_key               BIGINT IDENTITY(1,1) NOT NULL,
    delivery_id                VARCHAR(50)          NOT NULL,
    order_id                   VARCHAR(50)          NOT NULL,

    delivery_date_key          INT                  NOT NULL,
    customer_key               BIGINT               NOT NULL,
    restaurant_key             BIGINT               NOT NULL,
    delivery_partner_key       BIGINT               NOT NULL,

    order_item                 INT                  NULL,
    delivery_item              INT                  NULL,
    is_infull                  BIT                  NULL,

    prep_time                  INT                  NULL,
    rider_wait_time            INT                  NULL,
    travel_time                INT                  NULL,

    expected_delivery_time_min INT                  NULL,
    actual_delivery_time_min   INT                  NULL,
    delivery_delay_min         INT                  NULL,
    is_ontime                  BIT                  NULL,

    late_time                  INT                  NULL,
    prep_late_time             INT                  NULL,
    late_reason                VARCHAR(30)          NULL,
    is_otif                    BIT                  NULL,

    distance_km                DECIMAL(10,2)        NULL,
    distance_bins              VARCHAR(30)          NULL,
    travel_bins                VARCHAR(30)          NULL,
    prep_time_bins             VARCHAR(30)          NULL,
    actual_bins                VARCHAR(30)          NULL,

    batch_id                   BIGINT               NOT NULL,
    load_timestamp             DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_deliv_perf_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_delivery_performance
        PRIMARY KEY NONCLUSTERED (delivery_key),

    CONSTRAINT UQ_fact_delivery_performance_delivery_id
        UNIQUE NONCLUSTERED (delivery_id)
);
GO

/* Clustered Columnstore Index with Date Ordering for Vectorized Analytics */
CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_delivery_performance
    ON dwh.fact_delivery_performance
    ORDER (delivery_date_key);
GO


/* 5.4 DWH FACT RATING */
CREATE TABLE dwh.fact_rating
(
    rating_key           BIGINT IDENTITY(1,1) NOT NULL,
    rating_id            VARCHAR(50)          NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    rating_date_key      INT                  NOT NULL,
    rating_time_key      INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,
    delivery_partner_key BIGINT               NOT NULL,

    rating               DECIMAL(3,2)         NULL,
    rating_type_id       TINYINT              NULL,
    sentiment_score      DECIMAL(5,4)         NULL,
    sentiment_type_id    TINYINT              NULL,

    review_text          VARCHAR(4000)        NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_rating_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_rating
        PRIMARY KEY NONCLUSTERED (rating_key),

    CONSTRAINT UQ_fact_rating_id
        UNIQUE NONCLUSTERED (rating_id)
);
GO

/* Clustered Columnstore Index with Date Ordering for Vectorized Analytics */
CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_rating
    ON dwh.fact_rating
    ORDER (rating_date_key);
GO


/* 5.5 DWH FACT REVIEW ASPECT */
CREATE TABLE dwh.fact_review_aspect
(
    review_aspect_key    BIGINT IDENTITY(1,1) NOT NULL,
    rating_key           BIGINT               NOT NULL,

    aspect_id            TINYINT              NOT NULL,
    sentiment_type_id    TINYINT              NOT NULL,
    matched_phrase       VARCHAR(200)         NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_review_aspect_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_review_aspect
        PRIMARY KEY NONCLUSTERED (review_aspect_key)
);
GO

/* Clustered Columnstore Index for Review Aspects */
CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_review_aspect
    ON dwh.fact_review_aspect
    ORDER (rating_key);
GO


/* =========================================================
   6. INDEXES
   ========================================================= */

/* 6.1 SCD Type 2 Dimension Indexes */
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* Active record uniqueness */
CREATE UNIQUE NONCLUSTERED INDEX UQ_dim_customer_active
    ON dwh.dim_customer (customer_id)
    WHERE is_current = 1;

CREATE UNIQUE NONCLUSTERED INDEX UQ_dim_restaurant_active
    ON dwh.dim_restaurant (restaurant_id)
    WHERE is_current = 1;

CREATE UNIQUE NONCLUSTERED INDEX UQ_dim_delivery_partner_active
    ON dwh.dim_delivery_partner (delivery_partner_id)
    WHERE is_current = 1;

/* Point-in-Time Lookup optimization for Fact ETL JOINs */
CREATE NONCLUSTERED INDEX IX_dim_customer_pit_lookup
    ON dwh.dim_customer (customer_id, valid_from, valid_to)
    INCLUDE (customer_key);

CREATE NONCLUSTERED INDEX IX_dim_restaurant_pit_lookup
    ON dwh.dim_restaurant (restaurant_id, valid_from, valid_to)
    INCLUDE (restaurant_key);

CREATE NONCLUSTERED INDEX IX_dim_delivery_partner_pit_lookup
    ON dwh.dim_delivery_partner (delivery_partner_id, valid_from, valid_to)
    INCLUDE (delivery_partner_key);
GO

/* 6.2 Fact Indexes */

/* 6.2 Fact Table Storage & Index Architecture:
   - All 5 Fact Tables utilize Ordered Clustered Columnstore Indexes (CCI) as primary storage.
   - Vectorized Batch-Mode Execution optimizes large-scale Aggregations and Group By operations.
   - Single-row Point Lookups (e.g. order_id, delivery_id, rating_id) are handled by Nonclustered B-Tree Unique Indexes.
   - Redundant individual Foreign Key B-Tree indexes have been eliminated to prevent storage bloat and write penalties.
*/
GO


/* =========================================================
   7. VERIFICATION
   ========================================================= */

SELECT
    s.name AS schema_name,
    t.name AS table_name
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
WHERE s.name = 'dwh'
ORDER BY t.name;
GO


/* =========================================================
   8. TABLE ROW COUNT
   ========================================================= */

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.schemas s
    ON t.schema_id = s.schema_id
JOIN sys.partitions p
    ON t.object_id = p.object_id
WHERE s.name = 'dwh'
  AND p.index_id IN (0, 1)
GROUP BY
    s.name,
    t.name
ORDER BY
    t.name;
GO
