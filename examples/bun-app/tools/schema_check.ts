#!/usr/bin/env bun
/**
 * Schema consistency checker for task template YAML vs Zod schemas.
 *
 * Compares the JSON Schema declared in task template YAML files (input_schema
 * and per-step result_schema) against the JSON Schema derived from the Zod
 * schemas that handlers actually use at runtime.
 *
 * Usage:
 *   bun run tools/schema_check.ts                    # check all templates
 *   bun run tools/schema_check.ts --verbose          # show per-field details
 *   bun run tools/schema_check.ts --template payments
 */

import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { parseArgs } from "node:util";
import { parse as parseYaml } from "yaml";
import { zodToJsonSchema } from "zod-to-json-schema";
import type { ZodTypeAny } from "zod";

import {
  // Ecommerce
  EcommerceOrderProcessingInputSchema,
  EcommerceValidateCartResultSchema,
  EcommerceProcessPaymentResultSchema,
  EcommerceUpdateInventoryResultSchema,
  EcommerceCreateOrderResultSchema,
  EcommerceSendConfirmationResultSchema,
  // Data Pipeline
  AnalyticsPipelineInputSchema,
  PipelineExtractSalesResultSchema,
  PipelineExtractInventoryResultSchema,
  PipelineExtractCustomerResultSchema,
  PipelineTransformSalesResultSchema,
  PipelineTransformInventoryResultSchema,
  PipelineTransformCustomersResultSchema,
  PipelineAggregateMetricsResultSchema,
  PipelineGenerateInsightsResultSchema,
  // Microservices
  UserRegistrationInputSchema,
  MicroservicesCreateUserResultSchema,
  MicroservicesSetupBillingActiveResultSchema,
  MicroservicesInitPreferencesResultSchema,
  MicroservicesSendWelcomeResultSchema,
  MicroservicesUpdateStatusResultSchema,
  // Customer Success
  CustomerSuccessProcessRefundInputSchema,
  CustomerSuccessValidateRefundResultSchema,
  CustomerSuccessCheckRefundPolicyResultSchema,
  CustomerSuccessApproveRefundResultSchema,
  CustomerSuccessExecuteRefundResultSchema,
  CustomerSuccessUpdateTicketResultSchema,
  // Payments
  PaymentsProcessRefundInputSchema,
  PaymentsValidateEligibilityResultSchema,
  PaymentsProcessGatewayResultSchema,
  PaymentsUpdateRecordsResultSchema,
  PaymentsNotifyCustomerResultSchema,
} from "../src/services/schemas";

// ---------------------------------------------------------------------------
// Schema registry: maps template files to their Zod schemas
// ---------------------------------------------------------------------------

interface TemplateMapping {
  yamlFile: string;
  inputSchema: ZodTypeAny;
  stepSchemas: Record<string, ZodTypeAny>;
}

const SCHEMA_REGISTRY: TemplateMapping[] = [
  {
    yamlFile: "ecommerce_order_processing.yaml",
    inputSchema: EcommerceOrderProcessingInputSchema,
    stepSchemas: {
      validate_cart: EcommerceValidateCartResultSchema,
      process_payment: EcommerceProcessPaymentResultSchema,
      update_inventory: EcommerceUpdateInventoryResultSchema,
      create_order: EcommerceCreateOrderResultSchema,
      send_confirmation: EcommerceSendConfirmationResultSchema,
    },
  },
  {
    yamlFile: "data_pipeline_analytics_pipeline.yaml",
    inputSchema: AnalyticsPipelineInputSchema,
    stepSchemas: {
      extract_sales_data: PipelineExtractSalesResultSchema,
      extract_inventory_data: PipelineExtractInventoryResultSchema,
      extract_customer_data: PipelineExtractCustomerResultSchema,
      transform_sales: PipelineTransformSalesResultSchema,
      transform_inventory: PipelineTransformInventoryResultSchema,
      transform_customers: PipelineTransformCustomersResultSchema,
      aggregate_metrics: PipelineAggregateMetricsResultSchema,
      generate_insights: PipelineGenerateInsightsResultSchema,
    },
  },
  {
    yamlFile: "microservices_user_registration.yaml",
    inputSchema: UserRegistrationInputSchema,
    stepSchemas: {
      create_user_account: MicroservicesCreateUserResultSchema,
      setup_billing_profile: MicroservicesSetupBillingActiveResultSchema,
      initialize_preferences: MicroservicesInitPreferencesResultSchema,
      send_welcome_sequence: MicroservicesSendWelcomeResultSchema,
      update_user_status: MicroservicesUpdateStatusResultSchema,
    },
  },
  {
    yamlFile: "customer_success_process_refund.yaml",
    inputSchema: CustomerSuccessProcessRefundInputSchema,
    stepSchemas: {
      validate_refund_request: CustomerSuccessValidateRefundResultSchema,
      check_refund_policy: CustomerSuccessCheckRefundPolicyResultSchema,
      get_manager_approval: CustomerSuccessApproveRefundResultSchema,
      execute_refund_workflow: CustomerSuccessExecuteRefundResultSchema,
      update_ticket_status: CustomerSuccessUpdateTicketResultSchema,
    },
  },
  {
    yamlFile: "payments_process_refund.yaml",
    inputSchema: PaymentsProcessRefundInputSchema,
    stepSchemas: {
      validate_payment_eligibility: PaymentsValidateEligibilityResultSchema,
      process_gateway_refund: PaymentsProcessGatewayResultSchema,
      update_payment_records: PaymentsUpdateRecordsResultSchema,
      notify_customer: PaymentsNotifyCustomerResultSchema,
    },
  },
];

// ---------------------------------------------------------------------------
// Types for comparison results
// ---------------------------------------------------------------------------

enum MismatchKind {
  FieldMissingInCode = "field_missing_in_code",
  FieldMissingInYaml = "field_missing_in_yaml",
  TypeMismatch = "type_mismatch",
  RequiredMismatch = "required_mismatch",
}

interface FieldMismatch {
  fieldName: string;
  kind: MismatchKind;
  detail: string;
}

interface SchemaComparisonResult {
  templateFile: string;
  schemaLocation: string;
  schemaName: string;
  mismatches: FieldMismatch[];
}

function isOk(result: SchemaComparisonResult): boolean {
  return result.mismatches.length === 0;
}

// ---------------------------------------------------------------------------
// JSON Schema type normalization
// ---------------------------------------------------------------------------

const JSON_SCHEMA_TO_CANONICAL: Record<string, string> = {
  string: "string",
  number: "number",
  integer: "number",
  boolean: "boolean",
  array: "array",
  object: "object",
  null: "null",
};

function canonicalType(jsonSchemaType: string | string[] | undefined): string {
  if (jsonSchemaType === undefined) {
    return "any";
  }
  if (Array.isArray(jsonSchemaType)) {
    const types = jsonSchemaType
      .filter((t) => t !== "null")
      .map((t) => JSON_SCHEMA_TO_CANONICAL[t] ?? t);
    return types.length === 1 ? types[0] : "any";
  }
  return JSON_SCHEMA_TO_CANONICAL[jsonSchemaType] ?? jsonSchemaType;
}

function resolveZodFieldType(
  fieldSchema: Record<string, unknown>,
  defs: Record<string, Record<string, unknown>>,
): string {
  // Direct type
  if ("type" in fieldSchema) {
    return canonicalType(fieldSchema.type as string | string[]);
  }

  // $ref to a $defs entry
  if ("$ref" in fieldSchema) {
    const refPath = fieldSchema.$ref as string;
    const refName = refPath.split("/").pop()!;
    const refSchema = defs[refName] ?? {};
    return canonicalType(refSchema.type as string | string[] | undefined);
  }

  // anyOf — used by Zod for Optional types → anyOf: [{type: T}, {type: null}]
  if ("anyOf" in fieldSchema) {
    const variants = fieldSchema.anyOf as Record<string, unknown>[];
    const nonNull = variants.filter(
      (s) => s.type !== "null" && !(Array.isArray(s.type) && s.type.length === 1 && s.type[0] === "null"),
    );
    if (nonNull.length === 1) {
      return resolveZodFieldType(nonNull[0], defs);
    }
    return "any";
  }

  return "any";
}

// ---------------------------------------------------------------------------
// Schema extraction
// ---------------------------------------------------------------------------

interface NormalizedSchema {
  fields: Record<string, string>;
  required: Set<string>;
}

function normalizeYamlSchema(schema: Record<string, unknown>): NormalizedSchema {
  const properties = (schema.properties ?? {}) as Record<string, Record<string, unknown>>;
  const required = new Set<string>((schema.required as string[]) ?? []);
  const fields: Record<string, string> = {};

  for (const [name, prop] of Object.entries(properties)) {
    fields[name] = canonicalType(prop.type as string | string[] | undefined);
  }

  return { fields, required };
}

function normalizeZodSchema(zodSchema: ZodTypeAny): NormalizedSchema {
  const jsonSchema = zodToJsonSchema(zodSchema) as Record<string, unknown>;
  const defs = (jsonSchema.$defs ?? jsonSchema.definitions ?? {}) as Record<
    string,
    Record<string, unknown>
  >;
  const properties = (jsonSchema.properties ?? {}) as Record<string, Record<string, unknown>>;
  const required = new Set<string>((jsonSchema.required as string[]) ?? []);
  const fields: Record<string, string> = {};

  for (const [name, prop] of Object.entries(properties)) {
    fields[name] = resolveZodFieldType(prop, defs);
  }

  return { fields, required };
}

// ---------------------------------------------------------------------------
// Comparison logic
// ---------------------------------------------------------------------------

function compareSchemas(
  yamlSchema: NormalizedSchema,
  zodSchema: NormalizedSchema,
): FieldMismatch[] {
  const mismatches: FieldMismatch[] = [];
  const allFields = new Set([
    ...Object.keys(yamlSchema.fields),
    ...Object.keys(zodSchema.fields),
  ]);

  for (const fieldName of [...allFields].sort()) {
    const inYaml = fieldName in yamlSchema.fields;
    const inCode = fieldName in zodSchema.fields;

    if (!inCode) {
      mismatches.push({
        fieldName,
        kind: MismatchKind.FieldMissingInCode,
        detail: `declared in YAML (${yamlSchema.fields[fieldName]}) but not in Zod schema`,
      });
      continue;
    }

    if (!inYaml) {
      mismatches.push({
        fieldName,
        kind: MismatchKind.FieldMissingInYaml,
        detail: `in Zod schema (${zodSchema.fields[fieldName]}) but not declared in YAML`,
      });
      continue;
    }

    // Both present — compare types
    const yamlType = yamlSchema.fields[fieldName];
    const codeType = zodSchema.fields[fieldName];
    if (yamlType !== "any" && codeType !== "any" && yamlType !== codeType) {
      mismatches.push({
        fieldName,
        kind: MismatchKind.TypeMismatch,
        detail: `YAML says '${yamlType}', code says '${codeType}'`,
      });
    }

    // Compare required status
    const yamlReq = yamlSchema.required.has(fieldName);
    const codeReq = zodSchema.required.has(fieldName);
    if (yamlReq && !codeReq) {
      mismatches.push({
        fieldName,
        kind: MismatchKind.RequiredMismatch,
        detail: "required in YAML but optional in code",
      });
    }
  }

  return mismatches;
}

// ---------------------------------------------------------------------------
// Main check logic
// ---------------------------------------------------------------------------

const TEMPLATES_DIR = resolve(
  dirname(new URL(import.meta.url).pathname),
  "..",
  "src",
  "config",
  "templates",
);

function getSchemaName(zodSchema: ZodTypeAny): string {
  // Attempt to derive a readable name; fall back to "ZodSchema"
  const desc = zodSchema.description;
  if (desc) return desc;
  return "ZodSchema";
}

function checkTemplate(mapping: TemplateMapping): SchemaComparisonResult[] {
  const yamlPath = resolve(TEMPLATES_DIR, mapping.yamlFile);
  const yamlContent = readFileSync(yamlPath, "utf-8");
  const template = parseYaml(yamlContent) as Record<string, unknown>;

  const results: SchemaComparisonResult[] = [];

  // Check input_schema
  if (mapping.inputSchema && template.input_schema) {
    const yamlNorm = normalizeYamlSchema(template.input_schema as Record<string, unknown>);
    const codeNorm = normalizeZodSchema(mapping.inputSchema);
    const mismatches = compareSchemas(yamlNorm, codeNorm);
    results.push({
      templateFile: mapping.yamlFile,
      schemaLocation: "input_schema",
      schemaName: mapping.inputSchema.description ?? "InputSchema",
      mismatches,
    });
  }

  // Check each step's result_schema
  const steps = (template.steps ?? []) as Record<string, unknown>[];
  const stepsByName = new Map<string, Record<string, unknown>>();
  for (const step of steps) {
    stepsByName.set(step.name as string, step);
  }

  for (const [stepName, zodSchema] of Object.entries(mapping.stepSchemas)) {
    const schemaName = zodSchema.description ?? stepName;
    const step = stepsByName.get(stepName);

    if (!step) {
      results.push({
        templateFile: mapping.yamlFile,
        schemaLocation: `step:${stepName}`,
        schemaName,
        mismatches: [
          {
            fieldName: "<step>",
            kind: MismatchKind.FieldMissingInYaml,
            detail: `step '${stepName}' not found in template YAML`,
          },
        ],
      });
      continue;
    }

    const resultSchema = step.result_schema as Record<string, unknown> | undefined;
    if (!resultSchema) {
      results.push({
        templateFile: mapping.yamlFile,
        schemaLocation: `step:${stepName}.result_schema`,
        schemaName,
        mismatches: [
          {
            fieldName: "<schema>",
            kind: MismatchKind.FieldMissingInYaml,
            detail: "no result_schema declared in template YAML",
          },
        ],
      });
      continue;
    }

    const yamlNorm = normalizeYamlSchema(resultSchema);
    const codeNorm = normalizeZodSchema(zodSchema);
    const mismatches = compareSchemas(yamlNorm, codeNorm);
    results.push({
      templateFile: mapping.yamlFile,
      schemaLocation: `step:${stepName}.result_schema`,
      schemaName,
      mismatches,
    });
  }

  return results;
}

function checkAll(templateFilter?: string): SchemaComparisonResult[] {
  const allResults: SchemaComparisonResult[] = [];
  for (const mapping of SCHEMA_REGISTRY) {
    if (templateFilter && !mapping.yamlFile.startsWith(templateFilter)) {
      continue;
    }
    allResults.push(...checkTemplate(mapping));
  }
  return allResults;
}

// ---------------------------------------------------------------------------
// Output formatting
// ---------------------------------------------------------------------------

const KIND_SYMBOLS: Record<MismatchKind, string> = {
  [MismatchKind.FieldMissingInCode]: "- CODE",
  [MismatchKind.FieldMissingInYaml]: "- YAML",
  [MismatchKind.TypeMismatch]: "~ TYPE",
  [MismatchKind.RequiredMismatch]: "~ REQ ",
};

function printReport(results: SchemaComparisonResult[], verbose: boolean): number {
  const totalSchemas = results.length;
  const failedSchemas = results.filter((r) => !isOk(r));

  if (failedSchemas.length === 0) {
    console.log(`All ${totalSchemas} schemas consistent.`);
    return 0;
  }

  // Group by template file
  const byFile = new Map<string, SchemaComparisonResult[]>();
  for (const r of results) {
    const existing = byFile.get(r.templateFile) ?? [];
    existing.push(r);
    byFile.set(r.templateFile, existing);
  }

  for (const [templateFile, fileResults] of byFile) {
    const fileFails = fileResults.filter((r) => !isOk(r));
    if (fileFails.length === 0 && !verbose) {
      continue;
    }

    console.log(`\n${templateFile}`);
    for (const r of fileResults) {
      const status = isOk(r) ? "OK" : "MISMATCH";
      const count = !isOk(r) ? ` (${r.mismatches.length} issues)` : "";
      console.log(`  ${status} ${r.schemaLocation} <-> ${r.schemaName}${count}`);

      if (!isOk(r) || verbose) {
        for (const m of r.mismatches) {
          const symbol = KIND_SYMBOLS[m.kind] ?? "?";
          console.log(`    ${symbol}  ${m.fieldName}: ${m.detail}`);
        }
      }
    }
  }

  const okCount = totalSchemas - failedSchemas.length;
  console.log(
    `\n${okCount}/${totalSchemas} schemas consistent, ${failedSchemas.length} with mismatches.`,
  );
  return failedSchemas.length;
}

// ---------------------------------------------------------------------------
// CLI entry point
// ---------------------------------------------------------------------------

function main(): void {
  const { values } = parseArgs({
    args: Bun.argv.slice(2),
    options: {
      verbose: { type: "boolean", short: "v", default: false },
      template: { type: "string", short: "t" },
    },
    strict: true,
  });

  const results = checkAll(values.template);
  const failCount = printReport(results, values.verbose ?? false);
  process.exit(failCount > 0 ? 1 : 0);
}

main();
