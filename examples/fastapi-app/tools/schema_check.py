"""Schema consistency checker for task template YAML vs working Pydantic types.

Compares the JSON Schema declared in task template YAML files (input_schema and
per-step result_schema) against the JSON Schema derived from the Pydantic models
that handlers actually use at runtime.

Usage:
    uv run python -m tools.schema_check                # check all templates
    uv run python -m tools.schema_check --verbose      # show per-field details
    uv run python -m tools.schema_check --template payments_process_refund

Can also be imported and called from pytest (see tests/test_schema_consistency.py).
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel

from app.services.types import (
    # Ecommerce
    EcommerceOrderProcessingInput,
    EcommerceValidateCartResult,
    EcommerceProcessPaymentResult,
    EcommerceUpdateInventoryResult,
    EcommerceCreateOrderResult,
    EcommerceSendConfirmationResult,
    # Data Pipeline
    DataPipelineAnalyticsPipelineInput,
    PipelineExtractSalesResult,
    PipelineExtractInventoryResult,
    PipelineExtractCustomerResult,
    PipelineTransformSalesResult,
    PipelineTransformInventoryResult,
    PipelineTransformCustomersResult,
    PipelineAggregateMetricsResult,
    PipelineGenerateInsightsResult,
    # Microservices
    MicroservicesUserRegistrationInput,
    MicroservicesCreateUserResult,
    MicroservicesSetupBillingResult,
    MicroservicesInitPreferencesResult,
    MicroservicesSendWelcomeResult,
    MicroservicesUpdateStatusResult,
    # Customer Success
    CustomerSuccessProcessRefundInput,
    CustomerSuccessValidateRefundResult,
    CustomerSuccessCheckPolicyResult,
    CustomerSuccessApproveRefundResult,
    CustomerSuccessExecuteRefundResult,
    CustomerSuccessUpdateTicketResult,
    # Payments
    PaymentsProcessRefundInput,
    PaymentsValidateEligibilityResult,
    PaymentsProcessGatewayResult,
    PaymentsUpdateRecordsResult,
    PaymentsNotifyCustomerResult,
)


# ---------------------------------------------------------------------------
# Schema registry: maps template files to their Pydantic models
# ---------------------------------------------------------------------------


@dataclass
class TemplateMapping:
    """Maps a template YAML to its input model and per-step result models."""

    yaml_file: str
    input_model: type[BaseModel] | None = None
    step_models: dict[str, type[BaseModel]] = field(default_factory=dict)


SCHEMA_REGISTRY: list[TemplateMapping] = [
    TemplateMapping(
        yaml_file="ecommerce_order_processing.yaml",
        input_model=EcommerceOrderProcessingInput,
        step_models={
            "validate_cart": EcommerceValidateCartResult,
            "process_payment": EcommerceProcessPaymentResult,
            "update_inventory": EcommerceUpdateInventoryResult,
            "create_order": EcommerceCreateOrderResult,
            "send_confirmation": EcommerceSendConfirmationResult,
        },
    ),
    TemplateMapping(
        yaml_file="data_pipeline_analytics_pipeline.yaml",
        input_model=DataPipelineAnalyticsPipelineInput,
        step_models={
            "extract_sales_data": PipelineExtractSalesResult,
            "extract_inventory_data": PipelineExtractInventoryResult,
            "extract_customer_data": PipelineExtractCustomerResult,
            "transform_sales": PipelineTransformSalesResult,
            "transform_inventory": PipelineTransformInventoryResult,
            "transform_customers": PipelineTransformCustomersResult,
            "aggregate_metrics": PipelineAggregateMetricsResult,
            "generate_insights": PipelineGenerateInsightsResult,
        },
    ),
    TemplateMapping(
        yaml_file="microservices_user_registration.yaml",
        input_model=MicroservicesUserRegistrationInput,
        step_models={
            "create_user_account": MicroservicesCreateUserResult,
            "setup_billing_profile": MicroservicesSetupBillingResult,
            "initialize_preferences": MicroservicesInitPreferencesResult,
            "send_welcome_sequence": MicroservicesSendWelcomeResult,
            "update_user_status": MicroservicesUpdateStatusResult,
        },
    ),
    TemplateMapping(
        yaml_file="customer_success_process_refund.yaml",
        input_model=CustomerSuccessProcessRefundInput,
        step_models={
            "validate_refund_request": CustomerSuccessValidateRefundResult,
            "check_refund_policy": CustomerSuccessCheckPolicyResult,
            "get_manager_approval": CustomerSuccessApproveRefundResult,
            "execute_refund_workflow": CustomerSuccessExecuteRefundResult,
            "update_ticket_status": CustomerSuccessUpdateTicketResult,
        },
    ),
    TemplateMapping(
        yaml_file="payments_process_refund.yaml",
        input_model=PaymentsProcessRefundInput,
        step_models={
            "validate_payment_eligibility": PaymentsValidateEligibilityResult,
            "process_gateway_refund": PaymentsProcessGatewayResult,
            "update_payment_records": PaymentsUpdateRecordsResult,
            "notify_customer": PaymentsNotifyCustomerResult,
        },
    ),
]


# ---------------------------------------------------------------------------
# Types for comparison results
# ---------------------------------------------------------------------------


class MismatchKind(Enum):
    FIELD_MISSING_IN_CODE = "field_missing_in_code"
    FIELD_MISSING_IN_YAML = "field_missing_in_yaml"
    TYPE_MISMATCH = "type_mismatch"
    REQUIRED_MISMATCH = "required_mismatch"


@dataclass
class FieldMismatch:
    field_name: str
    kind: MismatchKind
    detail: str


@dataclass
class SchemaComparisonResult:
    template_file: str
    schema_location: str  # e.g. "input_schema" or "step:validate_cart.result_schema"
    model_name: str
    mismatches: list[FieldMismatch] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return len(self.mismatches) == 0


# ---------------------------------------------------------------------------
# JSON Schema type normalization
# ---------------------------------------------------------------------------

# Map from JSON Schema type strings to a canonical set for comparison
_JSON_SCHEMA_TO_CANONICAL = {
    "string": "string",
    "number": "number",
    "integer": "number",  # treat integer as compatible with number
    "boolean": "boolean",
    "array": "array",
    "object": "object",
    "null": "null",
}


def _canonical_type(json_schema_type: str | list | None) -> str:
    """Normalize a JSON Schema type to a canonical string for comparison."""
    if json_schema_type is None:
        return "any"
    if isinstance(json_schema_type, list):
        types = [_JSON_SCHEMA_TO_CANONICAL.get(t, t) for t in json_schema_type if t != "null"]
        return types[0] if len(types) == 1 else "any"
    return _JSON_SCHEMA_TO_CANONICAL.get(json_schema_type, json_schema_type)


def _resolve_pydantic_field_type(
    field_schema: dict[str, Any],
    defs: dict[str, Any],
) -> str:
    """Resolve a Pydantic JSON Schema field to a canonical type string.

    Handles $ref, anyOf (for Optional types), and direct type declarations.
    """
    # Direct type
    if "type" in field_schema:
        return _canonical_type(field_schema["type"])

    # $ref to a $defs entry
    if "$ref" in field_schema:
        ref_name = field_schema["$ref"].rsplit("/", 1)[-1]
        ref_schema = defs.get(ref_name, {})
        return _canonical_type(ref_schema.get("type"))

    # anyOf — used by Pydantic for Optional[T] → anyOf: [{type: T}, {type: null}]
    if "anyOf" in field_schema:
        non_null = [s for s in field_schema["anyOf"] if s.get("type") != "null"]
        if len(non_null) == 1:
            return _resolve_pydantic_field_type(non_null[0], defs)
        # Multiple non-null options — too complex, treat as any
        return "any"

    return "any"


# ---------------------------------------------------------------------------
# Schema extraction
# ---------------------------------------------------------------------------


@dataclass
class NormalizedSchema:
    """Flattened representation of a JSON Schema's top-level fields."""

    fields: dict[str, str]  # field_name -> canonical type
    required: set[str]


def normalize_yaml_schema(schema: dict[str, Any]) -> NormalizedSchema:
    """Extract top-level fields and types from a YAML-declared JSON Schema."""
    properties = schema.get("properties", {})
    required = set(schema.get("required", []))
    fields = {}
    for name, prop in properties.items():
        fields[name] = _canonical_type(prop.get("type"))
    return NormalizedSchema(fields=fields, required=required)


def normalize_pydantic_schema(model: type[BaseModel]) -> NormalizedSchema:
    """Extract top-level fields and types from a Pydantic model's JSON Schema."""
    schema = model.model_json_schema()
    defs = schema.get("$defs", {})
    properties = schema.get("properties", {})
    required = set(schema.get("required", []))
    fields = {}
    for name, prop in properties.items():
        fields[name] = _resolve_pydantic_field_type(prop, defs)
    return NormalizedSchema(fields=fields, required=required)


# ---------------------------------------------------------------------------
# Comparison logic
# ---------------------------------------------------------------------------


def compare_schemas(
    yaml_schema: NormalizedSchema,
    pydantic_schema: NormalizedSchema,
) -> list[FieldMismatch]:
    """Compare a YAML-declared schema against a Pydantic-derived schema."""
    mismatches: list[FieldMismatch] = []

    all_fields = set(yaml_schema.fields.keys()) | set(pydantic_schema.fields.keys())

    for field_name in sorted(all_fields):
        in_yaml = field_name in yaml_schema.fields
        in_code = field_name in pydantic_schema.fields

        if not in_code:
            mismatches.append(FieldMismatch(
                field_name=field_name,
                kind=MismatchKind.FIELD_MISSING_IN_CODE,
                detail=f"declared in YAML ({yaml_schema.fields[field_name]}) but not in Pydantic model",
            ))
            continue

        if not in_yaml:
            mismatches.append(FieldMismatch(
                field_name=field_name,
                kind=MismatchKind.FIELD_MISSING_IN_YAML,
                detail=f"in Pydantic model ({pydantic_schema.fields[field_name]}) but not declared in YAML",
            ))
            continue

        # Both present — compare types
        yaml_type = yaml_schema.fields[field_name]
        code_type = pydantic_schema.fields[field_name]
        if yaml_type != "any" and code_type != "any" and yaml_type != code_type:
            mismatches.append(FieldMismatch(
                field_name=field_name,
                kind=MismatchKind.TYPE_MISMATCH,
                detail=f"YAML says '{yaml_type}', code says '{code_type}'",
            ))

        # Compare required status
        yaml_req = field_name in yaml_schema.required
        code_req = field_name in pydantic_schema.required
        if yaml_req and not code_req:
            mismatches.append(FieldMismatch(
                field_name=field_name,
                kind=MismatchKind.REQUIRED_MISMATCH,
                detail="required in YAML but optional in code",
            ))

    return mismatches


# ---------------------------------------------------------------------------
# Main check logic
# ---------------------------------------------------------------------------


TEMPLATES_DIR = Path(__file__).resolve().parent.parent / "app" / "config" / "templates"


def check_template(mapping: TemplateMapping) -> list[SchemaComparisonResult]:
    """Check one template file against its registered Pydantic models."""
    yaml_path = TEMPLATES_DIR / mapping.yaml_file
    with open(yaml_path) as f:
        template = yaml.safe_load(f)

    results: list[SchemaComparisonResult] = []

    # Check input_schema
    if mapping.input_model is not None and "input_schema" in template:
        yaml_norm = normalize_yaml_schema(template["input_schema"])
        code_norm = normalize_pydantic_schema(mapping.input_model)
        mismatches = compare_schemas(yaml_norm, code_norm)
        results.append(SchemaComparisonResult(
            template_file=mapping.yaml_file,
            schema_location="input_schema",
            model_name=mapping.input_model.__name__,
            mismatches=mismatches,
        ))

    # Check each step's result_schema
    steps_by_name = {s["name"]: s for s in template.get("steps", [])}
    for step_name, model_cls in mapping.step_models.items():
        step = steps_by_name.get(step_name)
        if step is None:
            results.append(SchemaComparisonResult(
                template_file=mapping.yaml_file,
                schema_location=f"step:{step_name}",
                model_name=model_cls.__name__,
                mismatches=[FieldMismatch(
                    field_name="<step>",
                    kind=MismatchKind.FIELD_MISSING_IN_YAML,
                    detail=f"step '{step_name}' not found in template YAML",
                )],
            ))
            continue

        result_schema = step.get("result_schema")
        if result_schema is None:
            results.append(SchemaComparisonResult(
                template_file=mapping.yaml_file,
                schema_location=f"step:{step_name}.result_schema",
                model_name=model_cls.__name__,
                mismatches=[FieldMismatch(
                    field_name="<schema>",
                    kind=MismatchKind.FIELD_MISSING_IN_YAML,
                    detail="no result_schema declared in template YAML",
                )],
            ))
            continue

        yaml_norm = normalize_yaml_schema(result_schema)
        code_norm = normalize_pydantic_schema(model_cls)
        mismatches = compare_schemas(yaml_norm, code_norm)
        results.append(SchemaComparisonResult(
            template_file=mapping.yaml_file,
            schema_location=f"step:{step_name}.result_schema",
            model_name=model_cls.__name__,
            mismatches=mismatches,
        ))

    return results


def check_all(
    template_filter: str | None = None,
) -> list[SchemaComparisonResult]:
    """Check all registered templates (or a single one by filename prefix)."""
    all_results: list[SchemaComparisonResult] = []
    for mapping in SCHEMA_REGISTRY:
        if template_filter and not mapping.yaml_file.startswith(template_filter):
            continue
        all_results.extend(check_template(mapping))
    return all_results


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

_KIND_SYMBOLS = {
    MismatchKind.FIELD_MISSING_IN_CODE: "- CODE",
    MismatchKind.FIELD_MISSING_IN_YAML: "- YAML",
    MismatchKind.TYPE_MISMATCH: "~ TYPE",
    MismatchKind.REQUIRED_MISMATCH: "~ REQ ",
}


def print_report(results: list[SchemaComparisonResult], verbose: bool = False) -> int:
    """Print a human-readable report and return the count of schemas with mismatches."""
    total_schemas = len(results)
    failed_schemas = [r for r in results if not r.ok]

    if not failed_schemas:
        print(f"All {total_schemas} schemas consistent.")
        return 0

    # Group by template file
    by_file: dict[str, list[SchemaComparisonResult]] = {}
    for r in results:
        by_file.setdefault(r.template_file, []).append(r)

    for template_file, file_results in by_file.items():
        file_fails = [r for r in file_results if not r.ok]
        if not file_fails and not verbose:
            continue

        print(f"\n{template_file}")
        for r in file_results:
            status = "OK" if r.ok else "MISMATCH"
            count = f" ({len(r.mismatches)} issues)" if not r.ok else ""
            print(f"  {status} {r.schema_location} <-> {r.model_name}{count}")

            if not r.ok or verbose:
                for m in r.mismatches:
                    symbol = _KIND_SYMBOLS.get(m.kind, "?")
                    print(f"    {symbol}  {m.field_name}: {m.detail}")

    ok_count = total_schemas - len(failed_schemas)
    print(f"\n{ok_count}/{total_schemas} schemas consistent, "
          f"{len(failed_schemas)} with mismatches.")
    return len(failed_schemas)


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(description="Check template YAML schemas against Pydantic models")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show all schemas, not just failures")
    parser.add_argument("--template", "-t", type=str, default=None, help="Filter to a single template by filename prefix")
    args = parser.parse_args()

    results = check_all(template_filter=args.template)
    fail_count = print_report(results, verbose=args.verbose)
    sys.exit(1 if fail_count > 0 else 0)


if __name__ == "__main__":
    main()
