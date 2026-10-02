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


/* =========================================================
   1. CREATE DWH SCHEMA
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


/* =========================================================
   DROP EXISTING TABLES IN DEPENDENCY ORDER (FACTS THEN DIMS)
   ========================================================= */

DROP TABLE IF EXISTS dwh.fact_review_aspect;
DROP TABLE IF EXISTS dwh.fact_rating;
DROP TABLE IF EXISTS dwh.fact_delivery_performance;
DROP TABLE IF EXISTS dwh.fact_order_item;
DROP TABLE IF EXISTS dwh.fact_order;

DROP TABLE IF EXISTS dwh.dim_customer;
DROP TABLE IF EXISTS dwh.dim_restaurant;
DROP TABLE IF EXISTS dwh.dim_delivery_partner;
DROP TABLE IF EXISTS dwh.dim_menu_item;
DROP TABLE IF EXISTS dwh.dim_life_cycles;
DROP TABLE IF EXISTS dwh.dim_city;
DROP TABLE IF EXISTS dwh.dim_aspect;
DROP TABLE IF EXISTS dwh.dim_sentiment_type;
DROP TABLE IF EXISTS dwh.dim_rating_type;
DROP TABLE IF EXISTS dwh.dim_time;
DROP TABLE IF EXISTS dwh.dim_date;
GO


/* =========================================================
   2. DWH DIM DATE
   ========================================================= */

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


/* =========================================================
   3. DWH DIM TIME
   ========================================================= */

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
   3.1 DWH DIM LIFE CYCLES
   ========================================================= */

CREATE TABLE dwh.dim_life_cycles
(
    lc_id        TINYINT       NOT NULL,
    life_cycle   VARCHAR(50)   NOT NULL,
    description  VARCHAR(255)  NOT NULL,

    CONSTRAINT PK_dim_life_cycles
        PRIMARY KEY CLUSTERED (lc_id)
);
GO


/* =========================================================
   3.2 DWH DIM CITY
   ========================================================= */

CREATE TABLE dwh.dim_city
(
    city_id    INT          NOT NULL,
    city_code  VARCHAR(10)  NOT NULL,
    city_name  VARCHAR(100) NOT NULL,

    CONSTRAINT PK_dim_city
        PRIMARY KEY CLUSTERED (city_id),

    CONSTRAINT UQ_dim_city_code
        UNIQUE (city_code),

    CONSTRAINT UQ_dim_city_name
        UNIQUE (city_name)
);
GO


/* =========================================================
   4. DWH DIM CUSTOMER
   ========================================================= */

CREATE TABLE dwh.dim_customer
(
    customer_key            BIGINT IDENTITY(1,1) NOT NULL,
    customer_id             VARCHAR(50)          NOT NULL,
    signup_date             DATE                 NULL,
    city                    VARCHAR(100)         NULL,
    acquisition_channel     VARCHAR(100)         NULL,

    last_active             DATE                 NULL,
    days_since_last_active  INT                  NULL,
    churn_risk              VARCHAR(20)          NULL,
    life_cycle_id           TINYINT              NULL,
    last_status_id          TINYINT              NULL,
    is_churned              BIT                  NULL,
    churned_date            DATE                 NULL,

    batch_id                BIGINT               NOT NULL,
    load_timestamp          DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_customer_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_customer
        PRIMARY KEY CLUSTERED (customer_key),

    CONSTRAINT UQ_dim_customer_customer_id
        UNIQUE (customer_id),

    CONSTRAINT FK_dim_customer_life_cycle
        FOREIGN KEY (life_cycle_id) REFERENCES dwh.dim_life_cycles(lc_id),

    CONSTRAINT FK_dim_customer_last_status
        FOREIGN KEY (last_status_id) REFERENCES dwh.dim_life_cycles(lc_id)
);
GO


/* =========================================================
   5. DWH DIM RESTAURANT
   ========================================================= */

CREATE TABLE dwh.dim_restaurant
(
    restaurant_key          BIGINT IDENTITY(1,1) NOT NULL,
    restaurant_id           VARCHAR(50)          NOT NULL,
    onboard_date            DATE                 NULL,
    restaurant_name         VARCHAR(200)         NULL,
    city                    VARCHAR(100)         NULL,
    cuisine_type            VARCHAR(100)         NULL,
    partner_type            VARCHAR(100)         NULL,
    avg_prep_time_min       VARCHAR(50)          NULL,
    is_active               BIT                  NULL,

    min_prep_min            INT                  NULL,
    max_prep_min            INT                  NULL,
    prep_time_group         VARCHAR(50)          NULL,
    prep_time_index         TINYINT              NULL,
    last_active             DATE                 NULL,
    days_since_last_active  INT                  NULL,
    churn_risk              VARCHAR(20)          NULL,
    life_cycle_id           TINYINT              NULL,
    last_status_id          TINYINT              NULL,
    is_churned              BIT                  NULL,
    churned_date            DATE                 NULL,

    batch_id                BIGINT               NOT NULL,
    load_timestamp          DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_restaurant_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_restaurant
        PRIMARY KEY CLUSTERED (restaurant_key),

    CONSTRAINT UQ_dim_restaurant_restaurant_id
        UNIQUE (restaurant_id),

    CONSTRAINT FK_dim_restaurant_life_cycle
        FOREIGN KEY (life_cycle_id) REFERENCES dwh.dim_life_cycles(lc_id),

    CONSTRAINT FK_dim_restaurant_last_status
        FOREIGN KEY (last_status_id) REFERENCES dwh.dim_life_cycles(lc_id)
);
GO


/* =========================================================
   6. DWH DIM DELIVERY PARTNER
   ========================================================= */

CREATE TABLE dwh.dim_delivery_partner
(
    delivery_partner_key    BIGINT IDENTITY(1,1) NOT NULL,
    delivery_partner_id     VARCHAR(50)          NOT NULL,
    onboard_date            DATE                 NULL,
    partner_name            VARCHAR(200)         NULL,
    city                    VARCHAR(100)         NULL,
    vehicle_type            VARCHAR(100)         NULL,
    employment_type         VARCHAR(100)         NULL,
    avg_rating              DECIMAL(5,2)         NULL,
    is_active               BIT                  NULL,

    last_active             DATE                 NULL,
    days_since_last_active  INT                  NULL,
    churn_risk              VARCHAR(20)          NULL,
    life_cycle_id           TINYINT              NULL,
    last_status_id          TINYINT              NULL,
    is_churned              BIT                  NULL,
    churned_date            DATE                 NULL,
    rating_type_id          TINYINT              NULL,
    rating_type             VARCHAR(50)          NULL,

    batch_id                BIGINT               NOT NULL,
    load_timestamp          DATETIME2(3)         NOT NULL
        CONSTRAINT DF_dim_delivery_partner_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_dim_delivery_partner
        PRIMARY KEY CLUSTERED (delivery_partner_key),

    CONSTRAINT UQ_dim_delivery_partner_id
        UNIQUE (delivery_partner_id),

    CONSTRAINT FK_dim_delivery_partner_life_cycle
        FOREIGN KEY (life_cycle_id) REFERENCES dwh.dim_life_cycles(lc_id),

    CONSTRAINT FK_dim_delivery_partner_last_status
        FOREIGN KEY (last_status_id) REFERENCES dwh.dim_life_cycles(lc_id)
);
GO


/* =========================================================
   7. DWH DIM MENU ITEM
   ========================================================= */

CREATE TABLE dwh.dim_menu_item
(
    menu_item_key        BIGINT IDENTITY(1,1) NOT NULL,
    menu_item_id         VARCHAR(50)          NOT NULL,
    restaurant_id        VARCHAR(50)          NOT NULL,
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
        UNIQUE (menu_item_id)
);
GO


/* =========================================================
   8. DWH DIM RATING TYPE
   ========================================================= */

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


/* =========================================================
   9. DWH DIM SENTIMENT TYPE
   ========================================================= */

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


/* =========================================================
   10. DWH DIM ASPECT
   ========================================================= */

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
   11. DWH FACT ORDER
   ========================================================= */

CREATE TABLE dwh.fact_order
(
    order_key            BIGINT IDENTITY(1,1) NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    order_date_key       INT                  NOT NULL,
    order_time_key       INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,
    delivery_partner_key BIGINT               NOT NULL,

    customer_id          VARCHAR(50)          NOT NULL,
    restaurant_id        VARCHAR(50)          NOT NULL,
    delivery_partner_id  VARCHAR(50)          NULL,

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
        PRIMARY KEY CLUSTERED (order_key),

    CONSTRAINT UQ_fact_order_order_id
        UNIQUE (order_id),

    CONSTRAINT FK_fact_order_date
        FOREIGN KEY (order_date_key) REFERENCES dwh.dim_date(date_key),

    CONSTRAINT FK_fact_order_time
        FOREIGN KEY (order_time_key) REFERENCES dwh.dim_time(time_key),

    CONSTRAINT FK_fact_order_customer
        FOREIGN KEY (customer_key) REFERENCES dwh.dim_customer(customer_key),

    CONSTRAINT FK_fact_order_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dwh.dim_restaurant(restaurant_key),

    CONSTRAINT FK_fact_order_delivery_partner
        FOREIGN KEY (delivery_partner_key) REFERENCES dwh.dim_delivery_partner(delivery_partner_key)
);
GO


/* =========================================================
   12. DWH FACT ORDER ITEM
   ========================================================= */

CREATE TABLE dwh.fact_order_item
(
    order_item_key       BIGINT IDENTITY(1,1) NOT NULL,
    order_line_id        VARCHAR(50)          NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    order_date_key       INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,
    menu_item_key        BIGINT               NOT NULL,

    menu_item_id         VARCHAR(50)          NOT NULL,

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
        PRIMARY KEY CLUSTERED (order_item_key),

    CONSTRAINT UQ_fact_order_item_line_id
        UNIQUE (order_line_id),

    CONSTRAINT FK_fact_order_item_date
        FOREIGN KEY (order_date_key) REFERENCES dwh.dim_date(date_key),

    CONSTRAINT FK_fact_order_item_customer
        FOREIGN KEY (customer_key) REFERENCES dwh.dim_customer(customer_key),

    CONSTRAINT FK_fact_order_item_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dwh.dim_restaurant(restaurant_key),

    CONSTRAINT FK_fact_order_item_menu_item
        FOREIGN KEY (menu_item_key) REFERENCES dwh.dim_menu_item(menu_item_key)
);
GO


/* =========================================================
   13. DWH FACT DELIVERY PERFORMANCE
   ========================================================= */

CREATE TABLE dwh.fact_delivery_performance
(
    delivery_key               BIGINT IDENTITY(1,1) NOT NULL,
    delivery_id                VARCHAR(50)          NOT NULL,
    order_id                   VARCHAR(50)          NOT NULL,

    delivery_date_key          INT                  NOT NULL,
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
        PRIMARY KEY CLUSTERED (delivery_key),

    CONSTRAINT UQ_fact_delivery_performance_delivery_id
        UNIQUE (delivery_id),

    CONSTRAINT FK_fact_delivery_performance_date
        FOREIGN KEY (delivery_date_key) REFERENCES dwh.dim_date(date_key),

    CONSTRAINT FK_fact_delivery_performance_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dwh.dim_restaurant(restaurant_key),

    CONSTRAINT FK_fact_delivery_performance_delivery_partner
        FOREIGN KEY (delivery_partner_key) REFERENCES dwh.dim_delivery_partner(delivery_partner_key)
);
GO


/* =========================================================
   14. DWH FACT RATING
   ========================================================= */

CREATE TABLE dwh.fact_rating
(
    rating_key           BIGINT IDENTITY(1,1) NOT NULL,
    rating_id            VARCHAR(50)          NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    rating_date_key      INT                  NOT NULL,
    rating_time_key      INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,

    rating               DECIMAL(3,2)         NULL,
    rating_type_id       TINYINT              NULL,
    sentiment_score      DECIMAL(5,4)         NULL,
    sentiment_type_id    TINYINT              NULL,

    review_text          VARCHAR(2000)        NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_rating_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_rating
        PRIMARY KEY CLUSTERED (rating_key),

    CONSTRAINT UQ_fact_rating_id
        UNIQUE (rating_id),

    CONSTRAINT FK_fact_rating_date
        FOREIGN KEY (rating_date_key) REFERENCES dwh.dim_date(date_key),

    CONSTRAINT FK_fact_rating_time
        FOREIGN KEY (rating_time_key) REFERENCES dwh.dim_time(time_key),

    CONSTRAINT FK_fact_rating_customer
        FOREIGN KEY (customer_key) REFERENCES dwh.dim_customer(customer_key),

    CONSTRAINT FK_fact_rating_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dwh.dim_restaurant(restaurant_key),

    CONSTRAINT FK_fact_rating_type
        FOREIGN KEY (rating_type_id) REFERENCES dwh.dim_rating_type(rating_type_id),

    CONSTRAINT FK_fact_rating_sentiment_type
        FOREIGN KEY (sentiment_type_id) REFERENCES dwh.dim_sentiment_type(sentiment_type_id)
);
GO


/* =========================================================
   15. DWH FACT REVIEW ASPECT
   ========================================================= */

CREATE TABLE dwh.fact_review_aspect
(
    review_aspect_key    BIGINT IDENTITY(1,1) NOT NULL,
    rating_key           BIGINT               NOT NULL,
    rating_id            VARCHAR(50)          NOT NULL,
    order_id             VARCHAR(50)          NOT NULL,

    aspect_id            TINYINT              NOT NULL,
    sentiment_type_id    TINYINT              NOT NULL,
    matched_phrase       VARCHAR(200)         NULL,

    review_date_key      INT                  NOT NULL,
    customer_key         BIGINT               NOT NULL,
    restaurant_key       BIGINT               NOT NULL,

    batch_id             BIGINT               NOT NULL,
    load_timestamp       DATETIME2(3)         NOT NULL
        CONSTRAINT DF_fact_review_aspect_load_timestamp
        DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_fact_review_aspect
        PRIMARY KEY CLUSTERED (review_aspect_key),

    CONSTRAINT FK_fact_review_aspect_rating
        FOREIGN KEY (rating_key) REFERENCES dwh.fact_rating(rating_key),

    CONSTRAINT FK_fact_review_aspect_aspect
        FOREIGN KEY (aspect_id) REFERENCES dwh.dim_aspect(aspect_id),

    CONSTRAINT FK_fact_review_aspect_sentiment
        FOREIGN KEY (sentiment_type_id) REFERENCES dwh.dim_sentiment_type(sentiment_type_id),

    CONSTRAINT FK_fact_review_aspect_date
        FOREIGN KEY (review_date_key) REFERENCES dwh.dim_date(date_key),

    CONSTRAINT FK_fact_review_aspect_customer
        FOREIGN KEY (customer_key) REFERENCES dwh.dim_customer(customer_key),

    CONSTRAINT FK_fact_review_aspect_restaurant
        FOREIGN KEY (restaurant_key) REFERENCES dwh.dim_restaurant(restaurant_key)
);
GO

CREATE NONCLUSTERED INDEX IX_fact_review_aspect_rating_key
    ON dwh.fact_review_aspect (rating_key);

CREATE NONCLUSTERED INDEX IX_fact_review_aspect_aspect_id
    ON dwh.fact_review_aspect (aspect_id);

CREATE NONCLUSTERED INDEX IX_fact_review_aspect_sentiment_type_id
    ON dwh.fact_review_aspect (sentiment_type_id);

CREATE NONCLUSTERED INDEX IX_fact_review_aspect_customer_key
    ON dwh.fact_review_aspect (customer_key);

CREATE NONCLUSTERED INDEX IX_fact_review_aspect_restaurant_key
    ON dwh.fact_review_aspect (restaurant_key);

CREATE NONCLUSTERED INDEX IX_fact_review_aspect_review_date_key
    ON dwh.fact_review_aspect (review_date_key);
GO

/* Fact Order Indexes */
CREATE NONCLUSTERED INDEX IX_fact_order_order_date_key ON dwh.fact_order (order_date_key);
CREATE NONCLUSTERED INDEX IX_fact_order_order_time_key ON dwh.fact_order (order_time_key);
CREATE NONCLUSTERED INDEX IX_fact_order_customer_key ON dwh.fact_order (customer_key);
CREATE NONCLUSTERED INDEX IX_fact_order_restaurant_key ON dwh.fact_order (restaurant_key);
CREATE NONCLUSTERED INDEX IX_fact_order_delivery_partner_key ON dwh.fact_order (delivery_partner_key);
GO

/* Fact Order Item Indexes */
CREATE NONCLUSTERED INDEX IX_fact_order_item_order_date_key ON dwh.fact_order_item (order_date_key);
CREATE NONCLUSTERED INDEX IX_fact_order_item_customer_key ON dwh.fact_order_item (customer_key);
CREATE NONCLUSTERED INDEX IX_fact_order_item_restaurant_key ON dwh.fact_order_item (restaurant_key);
CREATE NONCLUSTERED INDEX IX_fact_order_item_menu_item_key ON dwh.fact_order_item (menu_item_key);
CREATE NONCLUSTERED INDEX IX_fact_order_item_order_id ON dwh.fact_order_item (order_id);
GO

/* Fact Delivery Performance Indexes */
CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_delivery_date_key ON dwh.fact_delivery_performance (delivery_date_key);
CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_restaurant_key ON dwh.fact_delivery_performance (restaurant_key);
CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_delivery_partner_key ON dwh.fact_delivery_performance (delivery_partner_key);
CREATE NONCLUSTERED INDEX IX_fact_delivery_performance_order_id ON dwh.fact_delivery_performance (order_id);
GO

/* Fact Rating Indexes */
CREATE NONCLUSTERED INDEX IX_fact_rating_rating_date_key ON dwh.fact_rating (rating_date_key);
CREATE NONCLUSTERED INDEX IX_fact_rating_rating_time_key ON dwh.fact_rating (rating_time_key);
CREATE NONCLUSTERED INDEX IX_fact_rating_customer_key ON dwh.fact_rating (customer_key);
CREATE NONCLUSTERED INDEX IX_fact_rating_restaurant_key ON dwh.fact_rating (restaurant_key);
CREATE NONCLUSTERED INDEX IX_fact_rating_rating_type_id ON dwh.fact_rating (rating_type_id);
CREATE NONCLUSTERED INDEX IX_fact_rating_sentiment_type_id ON dwh.fact_rating (sentiment_type_id);
CREATE NONCLUSTERED INDEX IX_fact_rating_order_id ON dwh.fact_rating (order_id);
GO


/* =========================================================
   16. VERIFICATION
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
   17. TABLE ROW COUNT
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
