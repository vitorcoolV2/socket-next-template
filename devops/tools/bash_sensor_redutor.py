import sys
import json
from jsonschema import validate, ValidationError

# Define the schema for validation
SCHEMA = {
    "type": "object",
    "properties": {
        "status": {"type": "string"},
        "exit_code": {"type": "integer"},
        "stdout": {"type": "string"},
        "tool": {
            "type": "object",
            "properties": {
                "cmd": {"type": "string"},
                "args": {"type": "array", "items": {"type": "string"}},
                "function": {"type": "string"},
                "script": {"type": "string"},
                "line": {"type": "integer"}
            },
            "required": ["cmd", "args", "function", "script", "line"]
        },
        "system": {
            "type": "object",
            "properties": {
                "hostname": {"type": "string"},
                "os": {"type": "string"},
                "kernel": {"type": "string"},
                "shell": {"type": "string"},
                "pid": {"type": "integer"},
                "parent_pid": {"type": "integer"},
                "timestamp": {"type": "string"},
                "cwd": {"type": "string"},
                "user": {"type": "string"}
            },
            "required": ["hostname", "os", "kernel", "shell", "pid", "parent_pid", "timestamp", "cwd", "user"]
        }
    },
    "required": ["status", "exit_code", "stdout", "tool", "system"]
}

def validate_and_save_ndjson(file_path):
    try:
        with open(file_path, 'r') as f:
            for line_number, line in enumerate(f, start=1):
                # Try to parse the line as JSON
                try:
                    data = json.loads(line.strip())
                except json.JSONDecodeError:
                    print(f"Line {line_number}: Invalid JSON")
                    continue

                # Validate the JSON against the schema
                try:
                    validate(instance=data, schema=SCHEMA)
                    print(f"Line {line_number}: Valid sensable Schema")

                    # Create a new JSON file for the valid line
                    output_file = f"/tmp/{file_path.split('/')[-1]}_{line_number}.json"
                    with open(output_file, 'w') as out_f:
                        json.dump(data, out_f, indent=4)

                    # Display the file path
                    print(f"{output_file}:{line_number}")
                except ValidationError as e:
                    print(f"Line {line_number}: Invalid - {e}")

    except FileNotFoundError:
        print(f"File not found: {file_path}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python ../tools/bash_sensor_redutor.py <ndjson_file>")
        sys.exit(1)

    ndjson_file = sys.argv[1]
    validate_and_save_ndjson(ndjson_file)