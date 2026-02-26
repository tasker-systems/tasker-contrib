//! Schema consistency tests: YAML task templates vs Rust struct types.
//!
//! Uses schemars to derive JSON Schema from Rust types and compares
//! against the JSON Schema declared in YAML task template files.
//!
//! Run: cargo test --test schema_consistency

use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::fmt;
use std::path::PathBuf;

use serde_json::Value;

use example_axum_app::types::*;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn templates_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("config/templates")
}

fn load_yaml_template(filename: &str) -> Value {
    let path = templates_dir().join(filename);
    let contents = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("Failed to read template {}: {e}", path.display()));
    serde_yaml::from_str(&contents)
        .unwrap_or_else(|e| panic!("Failed to parse YAML {}: {e}", path.display()))
}

// ---------------------------------------------------------------------------
// Normalized schema representation
// ---------------------------------------------------------------------------

/// A simplified representation of a JSON Schema object for comparison.
#[derive(Debug, Clone)]
struct NormalizedSchema {
    /// field_name -> canonical type string
    fields: BTreeMap<String, String>,
    /// set of required field names
    required: BTreeSet<String>,
}

// ---------------------------------------------------------------------------
// YAML schema normalization
// ---------------------------------------------------------------------------

fn normalize_yaml_schema(schema: &Value) -> NormalizedSchema {
    let mut fields = BTreeMap::new();
    let mut required = BTreeSet::new();

    if let Some(props) = schema.get("properties").and_then(|v| v.as_object()) {
        for (name, prop) in props {
            let ty = yaml_property_type(prop);
            fields.insert(name.clone(), ty);
        }
    }

    if let Some(req) = schema.get("required").and_then(|v| v.as_array()) {
        for r in req {
            if let Some(s) = r.as_str() {
                required.insert(s.to_string());
            }
        }
    }

    NormalizedSchema { fields, required }
}

fn yaml_property_type(prop: &Value) -> String {
    if let Some(ty) = prop.get("type").and_then(|v| v.as_str()) {
        canonical_type(ty).to_string()
    } else {
        "any".to_string()
    }
}

// ---------------------------------------------------------------------------
// JSON Schema (schemars) normalization
// ---------------------------------------------------------------------------

fn normalize_json_schema(schema: Value) -> NormalizedSchema {
    let mut fields = BTreeMap::new();
    let mut required = BTreeSet::new();

    // Build a lookup table for $defs / definitions so we can resolve $ref.
    let defs = resolve_definitions(&schema);

    // The root schema itself may be a $ref to a definition.
    let root = resolve_ref(&schema, &defs);

    if let Some(props) = root.get("properties").and_then(|v| v.as_object()) {
        for (name, prop) in props {
            let resolved = resolve_ref(prop, &defs);
            let ty = json_schema_property_type(resolved, &defs);
            fields.insert(name.clone(), ty);
        }
    }

    if let Some(req) = root.get("required").and_then(|v| v.as_array()) {
        for r in req {
            if let Some(s) = r.as_str() {
                required.insert(s.to_string());
            }
        }
    }

    NormalizedSchema { fields, required }
}

/// Collect definitions from `definitions` or `$defs` at the root level.
fn resolve_definitions(root: &Value) -> HashMap<String, Value> {
    let mut defs = HashMap::new();
    for key in &["definitions", "$defs"] {
        if let Some(obj) = root.get(*key).and_then(|v| v.as_object()) {
            for (name, val) in obj {
                defs.insert(name.clone(), val.clone());
            }
        }
    }
    defs
}

/// If `schema` contains a `$ref`, follow it into `defs`. Otherwise return as-is.
fn resolve_ref<'a>(schema: &'a Value, defs: &'a HashMap<String, Value>) -> &'a Value {
    if let Some(ref_str) = schema.get("$ref").and_then(|v| v.as_str()) {
        // e.g. "#/definitions/FooBar"
        let name = ref_str.rsplit('/').next().unwrap_or(ref_str);
        if let Some(resolved) = defs.get(name) {
            return resolved;
        }
    }
    schema
}

fn json_schema_property_type(prop: &Value, defs: &HashMap<String, Value>) -> String {
    // Direct type field
    if let Some(ty) = prop.get("type").and_then(|v| v.as_str()) {
        return canonical_type(ty).to_string();
    }

    // anyOf: [{type: T}, {type: "null"}] -> T (optional field pattern)
    if let Some(any_of) = prop.get("anyOf").and_then(|v| v.as_array()) {
        let non_null: Vec<&Value> = any_of
            .iter()
            .filter(|v| v.get("type").and_then(|t| t.as_str()) != Some("null"))
            .collect();
        if non_null.len() == 1 {
            let inner = resolve_ref(non_null[0], defs);
            return json_schema_property_type(inner, defs);
        }
    }

    // allOf with a single $ref (schemars wraps some types this way)
    if let Some(all_of) = prop.get("allOf").and_then(|v| v.as_array()) {
        if all_of.len() == 1 {
            let inner = resolve_ref(&all_of[0], defs);
            return json_schema_property_type(inner, defs);
        }
    }

    // $ref to a definition
    if prop.get("$ref").is_some() {
        let resolved = resolve_ref(prop, defs);
        if !std::ptr::eq(resolved, prop) {
            return json_schema_property_type(resolved, defs);
        }
    }

    "any".to_string()
}

// ---------------------------------------------------------------------------
// Canonical type mapping
// ---------------------------------------------------------------------------

fn canonical_type(json_schema_type: &str) -> &str {
    match json_schema_type {
        "string" => "string",
        "number" | "integer" => "number",
        "boolean" => "boolean",
        "array" => "array",
        "object" => "object",
        "null" => "null",
        other => other,
    }
}

// ---------------------------------------------------------------------------
// Mismatch detection
// ---------------------------------------------------------------------------

#[derive(Debug)]
enum Mismatch {
    /// Field present in YAML but missing from Rust type.
    MissingInCode { field: String },
    /// Field present in Rust type but missing from YAML.
    ExtraInCode { field: String },
    /// Field exists in both but canonical types differ.
    TypeMismatch {
        field: String,
        yaml_type: String,
        code_type: String,
    },
    /// Field is required in YAML but not in Rust (informational).
    RequiredMismatch {
        field: String,
        yaml_required: bool,
        code_required: bool,
    },
}

impl fmt::Display for Mismatch {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingInCode { field } => {
                write!(f, "  MISSING IN CODE: field `{field}` is in YAML but not in Rust type")
            }
            Self::ExtraInCode { field } => {
                write!(f, "  EXTRA IN CODE:   field `{field}` is in Rust type but not in YAML")
            }
            Self::TypeMismatch {
                field,
                yaml_type,
                code_type,
            } => {
                write!(
                    f,
                    "  TYPE MISMATCH:   field `{field}`: YAML={yaml_type}, Code={code_type}"
                )
            }
            Self::RequiredMismatch {
                field,
                yaml_required,
                code_required,
            } => {
                write!(
                    f,
                    "  REQUIRED DIFF:   field `{field}`: YAML required={yaml_required}, Code required={code_required}"
                )
            }
        }
    }
}

fn compare_schemas(yaml: &NormalizedSchema, code: &NormalizedSchema) -> Vec<Mismatch> {
    let mut mismatches = Vec::new();

    // Fields in YAML but not in code
    for field in yaml.fields.keys() {
        if !code.fields.contains_key(field) {
            mismatches.push(Mismatch::MissingInCode {
                field: field.clone(),
            });
        }
    }

    // Fields in code but not in YAML
    for field in code.fields.keys() {
        if !yaml.fields.contains_key(field) {
            mismatches.push(Mismatch::ExtraInCode {
                field: field.clone(),
            });
        }
    }

    // Type comparison for shared fields
    for (field, yaml_type) in &yaml.fields {
        if let Some(code_type) = code.fields.get(field) {
            if yaml_type != code_type {
                // Skip "any" comparisons — untyped YAML arrays or serde_json::Value
                if yaml_type != "any" && code_type != "any" {
                    mismatches.push(Mismatch::TypeMismatch {
                        field: field.clone(),
                        yaml_type: yaml_type.clone(),
                        code_type: code_type.clone(),
                    });
                }
            }
        }
    }

    // Required field differences (informational)
    let all_fields: BTreeSet<_> = yaml
        .fields
        .keys()
        .chain(code.fields.keys())
        .cloned()
        .collect();
    for field in &all_fields {
        let y_req = yaml.required.contains(field);
        let c_req = code.required.contains(field);
        if y_req != c_req {
            mismatches.push(Mismatch::RequiredMismatch {
                field: field.clone(),
                yaml_required: y_req,
                code_required: c_req,
            });
        }
    }

    mismatches
}

// ---------------------------------------------------------------------------
// Schema checking helpers
// ---------------------------------------------------------------------------

fn check_input_schema(template: &Value, code_schema: &Value) -> Vec<Mismatch> {
    let yaml_schema = template
        .get("input_schema")
        .expect("Template missing input_schema");
    let yaml_norm = normalize_yaml_schema(yaml_schema);
    let code_norm = normalize_json_schema(code_schema.clone());
    compare_schemas(&yaml_norm, &code_norm)
}

fn check_step_schema(template: &Value, step_name: &str, code_schema: &Value) -> Vec<Mismatch> {
    let steps = template
        .get("steps")
        .and_then(|v| v.as_array())
        .expect("Template missing steps array");

    let step = steps
        .iter()
        .find(|s| s.get("name").and_then(|v| v.as_str()) == Some(step_name))
        .unwrap_or_else(|| panic!("Step `{step_name}` not found in template"));

    let yaml_schema = step
        .get("result_schema")
        .expect("Step missing result_schema");
    let yaml_norm = normalize_yaml_schema(yaml_schema);
    let code_norm = normalize_json_schema(code_schema.clone());
    compare_schemas(&yaml_norm, &code_norm)
}

/// Collect all mismatches from multiple checks and assert with a descriptive message.
fn assert_no_mismatches(context: &str, all_mismatches: &[(String, Vec<Mismatch>)]) {
    let problem_schemas: Vec<_> = all_mismatches
        .iter()
        .filter(|(_, m)| !m.is_empty())
        .collect();

    if problem_schemas.is_empty() {
        return;
    }

    let mut msg = format!("\nSchema mismatches found in {context}:\n");
    for (label, mismatches) in &problem_schemas {
        msg.push_str(&format!("\n[{label}] ({} issue(s)):\n", mismatches.len()));
        for m in mismatches {
            msg.push_str(&format!("{m}\n"));
        }
    }

    panic!("{msg}");
}

// ---------------------------------------------------------------------------
// Per-template test functions
// ---------------------------------------------------------------------------

#[test]
fn ecommerce_schemas_consistent() {
    let template = load_yaml_template("ecommerce_order_processing.yaml");

    let mut results: Vec<(String, Vec<Mismatch>)> = Vec::new();

    results.push((
        "input_schema -> OrderProcessingInput".into(),
        check_input_schema(
            &template,
            &serde_json::to_value(schemars::schema_for!(ecommerce::OrderProcessingInput)).unwrap(),
        ),
    ));
    results.push((
        "validate_cart -> ValidateCartResult".into(),
        check_step_schema(
            &template,
            "validate_cart",
            &serde_json::to_value(schemars::schema_for!(ecommerce::ValidateCartResult)).unwrap(),
        ),
    ));
    results.push((
        "process_payment -> ProcessPaymentResult".into(),
        check_step_schema(
            &template,
            "process_payment",
            &serde_json::to_value(schemars::schema_for!(ecommerce::ProcessPaymentResult)).unwrap(),
        ),
    ));
    results.push((
        "update_inventory -> UpdateInventoryResult".into(),
        check_step_schema(
            &template,
            "update_inventory",
            &serde_json::to_value(schemars::schema_for!(ecommerce::UpdateInventoryResult))
                .unwrap(),
        ),
    ));
    results.push((
        "create_order -> CreateOrderResult".into(),
        check_step_schema(
            &template,
            "create_order",
            &serde_json::to_value(schemars::schema_for!(ecommerce::CreateOrderResult)).unwrap(),
        ),
    ));
    results.push((
        "send_confirmation -> SendConfirmationResult".into(),
        check_step_schema(
            &template,
            "send_confirmation",
            &serde_json::to_value(schemars::schema_for!(ecommerce::SendConfirmationResult))
                .unwrap(),
        ),
    ));

    assert_no_mismatches("ecommerce_order_processing", &results);
}

#[test]
fn data_pipeline_schemas_consistent() {
    let template = load_yaml_template("data_pipeline_analytics_pipeline.yaml");

    let mut results: Vec<(String, Vec<Mismatch>)> = Vec::new();

    results.push((
        "input_schema -> AnalyticsPipelineInput".into(),
        check_input_schema(
            &template,
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::AnalyticsPipelineInput
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "extract_sales_data -> ExtractSalesDataResult".into(),
        check_step_schema(
            &template,
            "extract_sales_data",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::ExtractSalesDataResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "extract_inventory_data -> ExtractInventoryDataResult".into(),
        check_step_schema(
            &template,
            "extract_inventory_data",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::ExtractInventoryDataResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "extract_customer_data -> ExtractCustomerDataResult".into(),
        check_step_schema(
            &template,
            "extract_customer_data",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::ExtractCustomerDataResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "transform_sales -> TransformSalesResult".into(),
        check_step_schema(
            &template,
            "transform_sales",
            &serde_json::to_value(schemars::schema_for!(data_pipeline::TransformSalesResult))
                .unwrap(),
        ),
    ));
    results.push((
        "transform_inventory -> TransformInventoryResult".into(),
        check_step_schema(
            &template,
            "transform_inventory",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::TransformInventoryResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "transform_customers -> TransformCustomersResult".into(),
        check_step_schema(
            &template,
            "transform_customers",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::TransformCustomersResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "aggregate_metrics -> AggregateMetricsResult".into(),
        check_step_schema(
            &template,
            "aggregate_metrics",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::AggregateMetricsResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "generate_insights -> GenerateInsightsResult".into(),
        check_step_schema(
            &template,
            "generate_insights",
            &serde_json::to_value(schemars::schema_for!(
                data_pipeline::GenerateInsightsResult
            ))
            .unwrap(),
        ),
    ));

    assert_no_mismatches("data_pipeline_analytics_pipeline", &results);
}

#[test]
fn microservices_schemas_consistent() {
    let template = load_yaml_template("microservices_user_registration.yaml");

    let mut results: Vec<(String, Vec<Mismatch>)> = Vec::new();

    results.push((
        "input_schema -> UserRegistrationInput".into(),
        check_input_schema(
            &template,
            &serde_json::to_value(schemars::schema_for!(
                microservices::UserRegistrationInput
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "create_user_account -> CreateUserAccountResult".into(),
        check_step_schema(
            &template,
            "create_user_account",
            &serde_json::to_value(schemars::schema_for!(
                microservices::CreateUserAccountResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "setup_billing_profile -> SetupBillingProfileResult".into(),
        check_step_schema(
            &template,
            "setup_billing_profile",
            &serde_json::to_value(schemars::schema_for!(
                microservices::SetupBillingProfileResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "initialize_preferences -> InitializePreferencesResult".into(),
        check_step_schema(
            &template,
            "initialize_preferences",
            &serde_json::to_value(schemars::schema_for!(
                microservices::InitializePreferencesResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "send_welcome_sequence -> SendWelcomeSequenceResult".into(),
        check_step_schema(
            &template,
            "send_welcome_sequence",
            &serde_json::to_value(schemars::schema_for!(
                microservices::SendWelcomeSequenceResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "update_user_status -> UpdateUserStatusResult".into(),
        check_step_schema(
            &template,
            "update_user_status",
            &serde_json::to_value(schemars::schema_for!(
                microservices::UpdateUserStatusResult
            ))
            .unwrap(),
        ),
    ));

    assert_no_mismatches("microservices_user_registration", &results);
}

#[test]
fn customer_success_schemas_consistent() {
    let template = load_yaml_template("customer_success_process_refund.yaml");

    let mut results: Vec<(String, Vec<Mismatch>)> = Vec::new();

    results.push((
        "input_schema -> ProcessRefundInput".into(),
        check_input_schema(
            &template,
            &serde_json::to_value(schemars::schema_for!(
                customer_success::ProcessRefundInput
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "validate_refund_request -> ValidateRefundRequestResult".into(),
        check_step_schema(
            &template,
            "validate_refund_request",
            &serde_json::to_value(schemars::schema_for!(
                customer_success::ValidateRefundRequestResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "check_refund_policy -> CheckRefundPolicyResult".into(),
        check_step_schema(
            &template,
            "check_refund_policy",
            &serde_json::to_value(schemars::schema_for!(
                customer_success::CheckRefundPolicyResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "get_manager_approval -> GetManagerApprovalResult".into(),
        check_step_schema(
            &template,
            "get_manager_approval",
            &serde_json::to_value(schemars::schema_for!(
                customer_success::GetManagerApprovalResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "execute_refund_workflow -> ExecuteRefundWorkflowResult".into(),
        check_step_schema(
            &template,
            "execute_refund_workflow",
            &serde_json::to_value(schemars::schema_for!(
                customer_success::ExecuteRefundWorkflowResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "update_ticket_status -> UpdateTicketStatusResult".into(),
        check_step_schema(
            &template,
            "update_ticket_status",
            &serde_json::to_value(schemars::schema_for!(
                customer_success::UpdateTicketStatusResult
            ))
            .unwrap(),
        ),
    ));

    assert_no_mismatches("customer_success_process_refund", &results);
}

#[test]
fn payments_schemas_consistent() {
    let template = load_yaml_template("payments_process_refund.yaml");

    let mut results: Vec<(String, Vec<Mismatch>)> = Vec::new();

    results.push((
        "input_schema -> ProcessRefundInput".into(),
        check_input_schema(
            &template,
            &serde_json::to_value(schemars::schema_for!(payments::ProcessRefundInput)).unwrap(),
        ),
    ));
    results.push((
        "validate_payment_eligibility -> ValidatePaymentEligibilityResult".into(),
        check_step_schema(
            &template,
            "validate_payment_eligibility",
            &serde_json::to_value(schemars::schema_for!(
                payments::ValidatePaymentEligibilityResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "process_gateway_refund -> ProcessGatewayRefundResult".into(),
        check_step_schema(
            &template,
            "process_gateway_refund",
            &serde_json::to_value(schemars::schema_for!(
                payments::ProcessGatewayRefundResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "update_payment_records -> UpdatePaymentRecordsResult".into(),
        check_step_schema(
            &template,
            "update_payment_records",
            &serde_json::to_value(schemars::schema_for!(
                payments::UpdatePaymentRecordsResult
            ))
            .unwrap(),
        ),
    ));
    results.push((
        "notify_customer -> NotifyCustomerResult".into(),
        check_step_schema(
            &template,
            "notify_customer",
            &serde_json::to_value(schemars::schema_for!(payments::NotifyCustomerResult)).unwrap(),
        ),
    ));

    assert_no_mismatches("payments_process_refund", &results);
}
