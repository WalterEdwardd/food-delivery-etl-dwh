"""Configuration for loading source files into staging tables."""

STAGING_CONFIG = {
    "customer": {
        "table": "stg.stg_customer",
        "columns": [
            "customer_id",
            "signup_date",
            "city",
            "acquisition_channel",
        ],
    },
    "delivery_partner": {
        "table": "stg.stg_delivery_partner",
        "columns": [
            "delivery_partner_id",
            "partner_name",
            "city",
            "vehicle_type",
            "employment_type",
            "avg_rating",
            "is_active",
        ],
    },
    "delivery_performance": {
        "table": "stg.stg_delivery_performance",
        "columns": [
            "delivery_id",
            "order_id",
            "order_item",
            "expected_delivery_time_min",
            "actual_delivery_time_min",
            "delivery_item",
            "distance_km",
        ],
    },
    "menu_item": {
        "table": "stg.stg_menu_item",
        "columns": [
            "menu_item_id",
            "restaurant_id",
            "item_name",
            "category",
            "is_veg",
            "price",
        ],
    },
    "order": {
        "table": "stg.stg_order",
        "columns": [
            "order_id",
            "customer_id",
            "restaurant_id",
            "delivery_partner_id",
            "order_timestamp",
            "subtotal_amount",
            "discount_amount",
            "delivery_fee",
            "total_amount",
            "is_cod",
            "is_cancelled",
        ],
    },
    "order_item": {
        "table": "stg.stg_order_item",
        "columns": [
            "order_line_id",
            "order_id",
            "menu_item_id",
            "restaurant_id",
            "quantity",
            "unit_price",
            "item_discount",
            "line_total",
        ],
    },
    "rating": {
        "table": "stg.stg_rating",
        "columns": [
            "rating_id",
            "order_id",
            "customer_id",
            "restaurant_id",
            "rating",
            "review_text",
            "review_timestamp",
            "sentiment_score",
        ],
    },
    "restaurant": {
        "table": "stg.stg_restaurant",
        "columns": [
            "restaurant_id",
            "restaurant_name",
            "city",
            "cuisine_type",
            "partner_type",
            "avg_prep_time_min",
            "is_active",
        ],
    },
}