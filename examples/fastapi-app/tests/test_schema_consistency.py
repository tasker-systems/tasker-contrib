"""Verify task template YAML schemas match Pydantic models in working code.

Catches drift between declared schemas (input_schema, result_schema) and the
types that handlers actually produce at runtime.

Run with: uv run pytest tests/test_schema_consistency.py -v
"""

from __future__ import annotations

import pytest

from tools.schema_check import SCHEMA_REGISTRY, check_template


@pytest.mark.parametrize(
    "mapping",
    SCHEMA_REGISTRY,
    ids=[m.yaml_file.removesuffix(".yaml") for m in SCHEMA_REGISTRY],
)
def test_template_schemas_match_code(mapping):
    """Each template's YAML schemas must be consistent with Pydantic models."""
    results = check_template(mapping)
    failures = [r for r in results if not r.ok]
    if failures:
        lines = []
        for r in failures:
            lines.append(f"\n  {r.schema_location} <-> {r.model_name}:")
            for m in r.mismatches:
                lines.append(f"    {m.kind.value}: {m.field_name} — {m.detail}")
        msg = f"{mapping.yaml_file}: {len(failures)} schema(s) inconsistent" + "".join(lines)
        pytest.fail(msg)
