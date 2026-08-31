from pathlib import Path

from src.config.source_schema import SOURCE_SCHEMA
from src.validation.file_validator import (
    summarize_results,
    validate_all_files,
)


def main():

    input_dir = Path(
        "C:/Users/PC/Downloads/food-delivery-etl-dwh/data/incoming"
    )

    results = validate_all_files(
        input_dir,
        SOURCE_SCHEMA,
    )

    for result in results:

        status = (
            "VALID"
            if result.is_valid
            else "INVALID"
        )

        print(
            f"[{status}] "
            f"{result.file_path.name}"
        )

        if result.source_name:
            print(
                f"  source: "
                f"{result.source_name}"
            )

        for error in result.errors:
            print(
                f"  error: {error}"
            )

    summary = summarize_results(
        results
    )

    print()
    print("Validation Summary")
    print("------------------")
    print(
        f"Total files   : "
        f"{summary['total_files']}"
    )
    print(
        f"Valid files   : "
        f"{summary['valid_files']}"
    )
    print(
        f"Invalid files : "
        f"{summary['invalid_files']}"
    )


if __name__ == "__main__":
    main()