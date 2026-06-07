import sys


def main():
    if len(sys.argv) < 2:
        print("Error: No version argument provided.")
        sys.exit(1)

    new_version = sys.argv[1]

    # We write VERSION to the root directory
    version_file_path = "VERSION"

    try:
        with open(version_file_path, "w") as f:
            f.write(new_version.strip())
        print(f"Successfully bumped version to: {new_version}")
    except Exception as e:
        print(f"Error writing VERSION file: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
