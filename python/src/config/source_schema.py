SOURCE_SCHEMA = {
    "customer": {
        "file_pattern": r"^customer_\d{8}\.csv$",
        "columns": {
            "customer_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "signup_date": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "city": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "acquisition_channel": {
                "source_type": "str",
                "required": False,
                "business_key": False,
            },
        },
    },

    "delivery_partner": {
        "file_pattern": r"^delivery_partner_\d{8}\.csv$",
        "columns": {
            "delivery_partner_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "partner_name": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "city": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "vehicle_type": {
                "source_type": "str",
                "required": False,
                "business_key": False,
            },
            "employment_type": {
                "source_type": "str",
                "required": False,
                "business_key": False,
            },
            "avg_rating": {
                "source_type": "float64",
                "required": False,
                "business_key": False,
            },
            "is_active": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
        },
    },

    "delivery_performance": {
        "file_pattern": r"^delivery_performance_\d{8}\.csv$",
        "columns": {
            "delivery_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
                "candidate_business_key": True,
            },
            "order_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "order_item": {
                "source_type": "int64",
                "required": True,
                "business_key": False,
            },
            "expected_delivery_time_min": {
                "source_type": "int64",
                "required": True,
                "business_key": False,
            },
            "actual_delivery_time_min": {
                "source_type": "int64",
                "required": True,
                "business_key": False,
            },
            "delivery_item": {
                "source_type": "int64",
                "required": True,
                "business_key": False,
            },
            "distance_km": {
                "source_type": "float64",
                "required": False,
                "business_key": False,
            },
        },
    },

    "menu_item": {
        "file_pattern": r"^menu_item_\d{8}\.csv$",
        "columns": {
            "menu_item_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "restaurant_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "item_name": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "category": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "is_veg": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "price": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
        },
    },

    "order": {
        "file_pattern": r"^order_\d{8}\.csv$",
        "columns": {
            "order_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "customer_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "restaurant_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "delivery_partner_id": {
                "source_type": "str",
                "required": False,
                "business_key": False,
            },
            "order_timestamp": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "subtotal_amount": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "discount_amount": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "delivery_fee": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "total_amount": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "is_cod": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "is_cancelled": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
        },
    },

    "order_item": {
        "file_pattern": r"^order_item_\d{8}\.csv$",
        "columns": {
            "order_line_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "order_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "menu_item_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "restaurant_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "quantity": {
                "source_type": "int64",
                "required": True,
                "business_key": False,
            },
            "unit_price": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "item_discount": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "line_total": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
        },
    },

    "rating": {
        "file_pattern": r"^rating_\d{8}\.csv$",
        "columns": {
            "rating_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "order_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "customer_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "restaurant_id": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "rating": {
                "source_type": "float64",
                "required": True,
                "business_key": False,
            },
            "review_text": {
                "source_type": "str",
                "required": False,
                "business_key": False,
            },
            "review_timestamp": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "sentiment_score": {
                "source_type": "float64",
                "required": False,
                "business_key": False,
            },
        },
    },

    "restaurant": {
        "file_pattern": r"^restaurant_\d{8}\.csv$",
        "columns": {
            "restaurant_id": {
                "source_type": "str",
                "required": True,
                "business_key": True,
            },
            "restaurant_name": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "city": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "cuisine_type": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "partner_type": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "avg_prep_time_min": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
            "is_active": {
                "source_type": "str",
                "required": True,
                "business_key": False,
            },
        },
    },
}