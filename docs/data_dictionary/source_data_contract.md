# Source Data Contract

## 1. Purpose

This document defines the expected structure and basic
validation requirements for the Food Delivery CSV source files.

The contract is used as the reference for:

- Source file validation
- Source schema validation
- STG table design
- Data quality validation
- Data lineage
- ETL development

## 2. Source Format

| Attribute | Specification |
|---|---|
| File format | CSV |
| Filename convention | `<entity>_YYYYMMDD.csv` |
| Header row | Required |
| Encoding | TBD |
| Delimiter | TBD |
| Quote character | TBD |

## 3. Source Entities

The current source contains 8 entities:

1. customer
2. delivery_partner
3. delivery_performance
4. menu_item
5. order
6. order_item
7. rating
8. restaurant

## 4. Validation Levels

### 4.1 File-Level Validation

The pipeline should validate:

- File exists.
- Filename follows the expected pattern.
- File extension is `.csv`.
- File is readable.

### 4.2 Schema-Level Validation

The pipeline should validate:

- Required columns exist.
- Unexpected columns are identified.
- Column names match the contract.
- Source structure matches the expected schema.

### 4.3 Data-Level Validation

The pipeline should validate:

- Required business keys are not null or empty.
- Numeric values are valid.
- Date/time values are parseable.
- Business validation rules are evaluated.

## 5. Customer

### Filename

`customer_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| customer_id | str | Yes | Yes |
| signup_date | str | Yes | No |
| city | str | Yes | No |
| acquisition_channel | str | No | No |

## 6. Delivery Partner

### Filename

`delivery_partner_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| delivery_partner_id | str | Yes | Yes |
| partner_name | str | Yes | No |
| city | str | Yes | No |
| vehicle_type | str | No | No |
| employment_type | str | No | No |
| avg_rating | float64 | No | No |
| is_active | str | Yes | No |

## 7. Delivery Performance

### Filename

`delivery_performance_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| delivery_id | str | Yes | Candidate |
| order_id | str | Yes | No |
| order_item | int64 | Yes | No |
| expected_delivery_time_min | int64 | Yes | No |
| actual_delivery_time_min | int64 | Yes | No |
| delivery_item | int64 | Yes | No |
| distance_km | float64 | No | No |

### Key Note

`delivery_id` is currently treated as a candidate business key.
Uniqueness should be verified through data profiling.

## 8. Menu Item

### Filename

`menu_item_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| menu_item_id | str | Yes | Yes |
| restaurant_id | str | Yes | No |
| item_name | str | Yes | No |
| category | str | Yes | No |
| is_veg | str | Yes | No |
| price | float64 | Yes | No |

## 9. Order

### Filename

`order_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| order_id | str | Yes | Yes |
| customer_id | str | Yes | No |
| restaurant_id | str | Yes | No |
| delivery_partner_id | str | No | No |
| order_timestamp | str | Yes | No |
| subtotal_amount | float64 | Yes | No |
| discount_amount | float64 | Yes | No |
| delivery_fee | float64 | Yes | No |
| total_amount | float64 | Yes | No |
| is_cod | str | Yes | No |
| is_cancelled | str | Yes | No |

## 10. Order Item

### Filename

`order_item_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| order_line_id | str | Yes | Yes |
| order_id | str | Yes | No |
| menu_item_id | str | Yes | No |
| restaurant_id | str | Yes | No |
| quantity | int64 | Yes | No |
| unit_price | float64 | Yes | No |
| item_discount | float64 | Yes | No |
| line_total | float64 | Yes | No |

## 11. Rating

### Filename

`rating_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| rating_id | str | Yes | Yes |
| order_id | str | Yes | No |
| customer_id | str | Yes | No |
| restaurant_id | str | Yes | No |
| rating | float64 | Yes | No |
| review_text | str | No | No |
| review_timestamp | str | Yes | No |
| sentiment_score | float64 | No | No |

### Data Quality Rule

`rating` should be evaluated against the expected business range:

`1 <= rating <= 5`

## 12. Restaurant

### Filename

`restaurant_YYYYMMDD.csv`

### Columns

| Column | Source Type | Required | Business Key |
|---|---|---:|---:|
| restaurant_id | str | Yes | Yes |
| restaurant_name | str | Yes | No |
| city | str | Yes | No |
| cuisine_type | str | Yes | No |
| partner_type | str | Yes | No |
| avg_prep_time_min | str | Yes | No |
| is_active | str | Yes | No |

## 13. Initial Data Quality Rules

The following rules are identified from the current source specification.

### Customer

- `customer_id` should not be null or empty.

### Restaurant

- `restaurant_id` should not be null or empty.
- `avg_prep_time_min` should be validated as numeric during transformation.

### Menu Item

- `menu_item_id` should not be null or empty.
- `price` should be validated as a non-negative numeric value.

### Order

- `order_id` should not be null or empty.
- Date/time fields must be parseable.

### Order Item

- `order_line_id` should not be null or empty.
- `quantity` should be validated as greater than zero.
- Monetary values should be validated as numeric.

### Delivery Performance

- `delivery_id` should not be null or empty.
- Time-related numeric values should be validated.
- `distance_km` should be validated as non-negative.

### Rating

- `rating_id` should not be null or empty.
- `rating` should be between 1 and 5.

## 14. Assumptions and TBD

The following source characteristics have not yet been formally specified:

- File encoding
- CSV delimiter
- Quote character
- Exact date format
- Exact datetime format
- Definitive uniqueness constraints for candidate keys
- Definitive nullability rules for all columns

These items must be verified before being treated as production source contracts.