import pathlib
import sys
import tomllib

root = pathlib.Path(__file__).resolve().parent
name = sys.argv[1]
layer = root / name


def merge(base: dict, override: dict) -> dict:
    for key, val in override.items():
        if isinstance(val, dict) and isinstance(base.get(key), dict):
            merge(base[key], val)
        else:
            base[key] = val
    return base


def format_value(val) -> str:
    if isinstance(val, bool):
        return "true" if val else "false"
    if isinstance(val, str):
        return f'"{val}"'
    if isinstance(val, list):
        if not val:
            return "[]"
        items = ",\n".join(f"    {format_value(item)}" for item in val)
        return f"[\n{items},\n]"
    return str(val)


def dump_sections(data: dict, prefix: str = "") -> list[str]:
    lines = []
    for key, val in data.items():
        if not isinstance(val, dict):
            continue
        section = f"{prefix}.{key}" if prefix else key
        if all(not isinstance(v, dict) for v in val.values()):
            lines.append(f"[{section}]")
            for item_key, item_val in val.items():
                formatted = format_value(item_val)
                lines.append(f"{item_key} = {formatted}")
            lines.append("")
        else:
            lines.extend(dump_sections(val, section))
    return lines


config = tomllib.loads((root / "template.toml").read_text())
layer_toml = layer / ".toml"
if layer_toml.exists():
    merge(config, tomllib.loads(layer_toml.read_text()))
else:
    merge(config, {"project": {"dependencies": [name]}})

(layer / "pyproject.toml").write_text("\n".join(dump_sections(config)))
