#!/usr/bin/env ruby
# frozen_string_literal: true

# Schema consistency checker for task template YAML vs working Dry::Struct types.
#
# Compares the JSON Schema declared in task template YAML files (input_schema and
# per-step result_schema) against the attributes declared on the Dry::Struct models
# that handlers actually use at runtime.
#
# Usage:
#   bundle exec ruby tools/schema_check.rb                    # check all templates
#   bundle exec ruby tools/schema_check.rb --verbose          # show per-field details
#   bundle exec ruby tools/schema_check.rb --template payments
#
# Can also be required and called from RSpec (see spec/tools/schema_consistency_spec.rb).

require_relative '../config/environment'
require 'yaml'
require 'optparse'
require 'set'

module SchemaCheck
  # ---------------------------------------------------------------------------
  # Schema registry: maps template files to their Dry::Struct models
  # ---------------------------------------------------------------------------

  TemplateMapping = Struct.new(:yaml_file, :input_model, :step_models, keyword_init: true)

  SCHEMA_REGISTRY = [
    TemplateMapping.new(
      yaml_file: 'ecommerce_order_processing.yaml',
      input_model: Types::EcommerceOrderProcessingInput,
      step_models: {
        'validate_cart' => Types::Ecommerce::ValidateCartResult,
        'process_payment' => Types::Ecommerce::ProcessPaymentResult,
        'update_inventory' => Types::Ecommerce::UpdateInventoryResult,
        'create_order' => Types::Ecommerce::CreateOrderResult,
        'send_confirmation' => Types::Ecommerce::SendConfirmationResult
      }
    ),
    TemplateMapping.new(
      yaml_file: 'data_pipeline_analytics_pipeline.yaml',
      input_model: Types::DataPipelineAnalyticsPipelineInput,
      step_models: {
        'extract_sales_data' => Types::DataPipeline::ExtractSalesResult,
        'extract_inventory_data' => Types::DataPipeline::ExtractInventoryResult,
        'extract_customer_data' => Types::DataPipeline::ExtractCustomerResult,
        'transform_sales' => Types::DataPipeline::TransformSalesResult,
        'transform_inventory' => Types::DataPipeline::TransformInventoryResult,
        'transform_customers' => Types::DataPipeline::TransformCustomersResult,
        'aggregate_metrics' => Types::DataPipeline::AggregateMetricsResult,
        'generate_insights' => Types::DataPipeline::GenerateInsightsResult
      }
    ),
    TemplateMapping.new(
      yaml_file: 'microservices_user_registration.yaml',
      input_model: Types::MicroservicesUserRegistrationInput,
      step_models: {
        'create_user_account' => Types::Microservices::CreateUserResult,
        'setup_billing_profile' => Types::Microservices::SetupBillingResult,
        'initialize_preferences' => Types::Microservices::InitPreferencesResult,
        'send_welcome_sequence' => Types::Microservices::SendWelcomeResult,
        'update_user_status' => Types::Microservices::UpdateStatusResult
      }
    ),
    TemplateMapping.new(
      yaml_file: 'customer_success_process_refund.yaml',
      input_model: Types::CustomerSuccessProcessRefundInput,
      step_models: {
        'validate_refund_request' => Types::CustomerSuccess::ValidateRefundResult,
        'check_refund_policy' => Types::CustomerSuccess::CheckPolicyResult,
        'get_manager_approval' => Types::CustomerSuccess::ApproveRefundResult,
        'execute_refund_workflow' => Types::CustomerSuccess::ExecuteRefundResult,
        'update_ticket_status' => Types::CustomerSuccess::UpdateTicketResult
      }
    ),
    TemplateMapping.new(
      yaml_file: 'payments_process_refund.yaml',
      input_model: Types::PaymentsProcessRefundInput,
      step_models: {
        'validate_payment_eligibility' => Types::Payments::ValidateEligibilityResult,
        'process_gateway_refund' => Types::Payments::ProcessGatewayResult,
        'update_payment_records' => Types::Payments::UpdateRecordsResult,
        'notify_customer' => Types::Payments::NotifyCustomerResult
      }
    )
  ].freeze

  # ---------------------------------------------------------------------------
  # Types for comparison results
  # ---------------------------------------------------------------------------

  module MismatchKind
    FIELD_MISSING_IN_CODE = :field_missing_in_code
    FIELD_MISSING_IN_YAML = :field_missing_in_yaml
    TYPE_MISMATCH         = :type_mismatch
    REQUIRED_MISMATCH     = :required_mismatch
  end

  FieldMismatch = Struct.new(:field_name, :kind, :detail, keyword_init: true)

  SchemaComparisonResult = Struct.new(:template_file, :schema_location, :model_name, :mismatches,
                                     keyword_init: true) do
    def ok?
      mismatches.empty?
    end
  end

  # ---------------------------------------------------------------------------
  # JSON Schema type normalization
  # ---------------------------------------------------------------------------

  JSON_SCHEMA_TO_CANONICAL = {
    'string'  => 'string',
    'number'  => 'number',
    'integer' => 'number', # treat integer as compatible with number
    'boolean' => 'boolean',
    'array'   => 'array',
    'object'  => 'object',
    'null'    => 'null'
  }.freeze

  def self.canonical_type(json_schema_type)
    return 'any' if json_schema_type.nil?

    if json_schema_type.is_a?(Array)
      types = json_schema_type.reject { |t| t == 'null' }.map { |t| JSON_SCHEMA_TO_CANONICAL[t] || t }
      return types.size == 1 ? types.first : 'any'
    end

    JSON_SCHEMA_TO_CANONICAL[json_schema_type.to_s] || json_schema_type.to_s
  end

  # ---------------------------------------------------------------------------
  # Dry::Types → canonical type mapping
  # ---------------------------------------------------------------------------

  DRY_TYPE_TO_CANONICAL = {
    'String'  => 'string',
    'Integer' => 'number',
    'Float'   => 'number',
    'Decimal' => 'number',
    'Bool'    => 'boolean',
    'Array'   => 'array',
    'Hash'    => 'object',
    'Date'    => 'string',
    'Time'    => 'string',
    'DateTime' => 'string'
  }.freeze

  def self.dry_type_to_canonical(type)
    # Unwrap optional types: Type.optional wraps with Sum(Type | NilClass)
    type_str = type.to_s

    # Strip optional wrappers
    type_str = type_str.gsub(/\[.*?\]/, '') # remove parameterized part like [Integer]
    type_str = type_str.gsub(/\s*\|\s*NilClass/, '') # remove | NilClass from Sum
    type_str = type_str.gsub(/^Sum</, '').gsub(/>$/, '')

    # Match known type names
    DRY_TYPE_TO_CANONICAL.each do |dry_name, canonical|
      return canonical if type_str.include?(dry_name)
    end

    # If it references another Dry::Struct, treat as object
    return 'object' if type_str.include?('Struct') || type_str.include?('Types::')

    'any'
  end

  # ---------------------------------------------------------------------------
  # Schema extraction
  # ---------------------------------------------------------------------------

  NormalizedSchema = Struct.new(:fields, :required, keyword_init: true)

  def self.normalize_yaml_schema(schema)
    properties = schema['properties'] || {}
    required = Set.new(schema['required'] || [])
    fields = {}
    properties.each do |name, prop|
      fields[name] = canonical_type(prop['type'])
    end
    NormalizedSchema.new(fields: fields, required: required)
  end

  def self.normalize_dry_struct(klass)
    fields = {}
    klass.schema.each do |attr_def|
      name = attr_def.name.to_s
      fields[name] = dry_type_to_canonical(attr_def.type)
    end
    # ResultStruct makes everything optional/omittable, so required is empty
    # InputStruct also makes everything optional. Only strict types would have required.
    required = Set.new
    NormalizedSchema.new(fields: fields, required: required)
  end

  # ---------------------------------------------------------------------------
  # Comparison logic
  # ---------------------------------------------------------------------------

  def self.compare_schemas(yaml_schema, struct_schema)
    mismatches = []
    all_fields = (yaml_schema.fields.keys + struct_schema.fields.keys).uniq.sort

    all_fields.each do |field_name|
      in_yaml = yaml_schema.fields.key?(field_name)
      in_code = struct_schema.fields.key?(field_name)

      unless in_code
        mismatches << FieldMismatch.new(
          field_name: field_name,
          kind: MismatchKind::FIELD_MISSING_IN_CODE,
          detail: "declared in YAML (#{yaml_schema.fields[field_name]}) but not in Dry::Struct"
        )
        next
      end

      unless in_yaml
        mismatches << FieldMismatch.new(
          field_name: field_name,
          kind: MismatchKind::FIELD_MISSING_IN_YAML,
          detail: "in Dry::Struct (#{struct_schema.fields[field_name]}) but not declared in YAML"
        )
        next
      end

      # Both present — compare types
      yaml_type = yaml_schema.fields[field_name]
      code_type = struct_schema.fields[field_name]
      if yaml_type != 'any' && code_type != 'any' && yaml_type != code_type
        mismatches << FieldMismatch.new(
          field_name: field_name,
          kind: MismatchKind::TYPE_MISMATCH,
          detail: "YAML says '#{yaml_type}', code says '#{code_type}'"
        )
      end

      # Compare required status (only flag if YAML says required but code doesn't)
      yaml_req = yaml_schema.required.include?(field_name)
      code_req = struct_schema.required.include?(field_name)
      next unless yaml_req && !code_req

      mismatches << FieldMismatch.new(
        field_name: field_name,
        kind: MismatchKind::REQUIRED_MISMATCH,
        detail: 'required in YAML but optional in code'
      )
    end

    mismatches
  end

  # ---------------------------------------------------------------------------
  # Main check logic
  # ---------------------------------------------------------------------------

  TEMPLATES_DIR = File.expand_path('../config/tasker/templates', __dir__)

  def self.check_template(mapping)
    yaml_path = File.join(TEMPLATES_DIR, mapping.yaml_file)
    template = YAML.safe_load(File.read(yaml_path))
    results = []

    # Check input_schema
    if mapping.input_model && template['input_schema']
      yaml_norm = normalize_yaml_schema(template['input_schema'])
      code_norm = normalize_dry_struct(mapping.input_model)
      mismatches = compare_schemas(yaml_norm, code_norm)
      results << SchemaComparisonResult.new(
        template_file: mapping.yaml_file,
        schema_location: 'input_schema',
        model_name: mapping.input_model.name,
        mismatches: mismatches
      )
    end

    # Check each step's result_schema
    steps_by_name = (template['steps'] || []).each_with_object({}) { |s, h| h[s['name']] = s }
    mapping.step_models.each do |step_name, model_cls|
      step = steps_by_name[step_name]
      if step.nil?
        results << SchemaComparisonResult.new(
          template_file: mapping.yaml_file,
          schema_location: "step:#{step_name}",
          model_name: model_cls.name,
          mismatches: [FieldMismatch.new(
            field_name: '<step>',
            kind: MismatchKind::FIELD_MISSING_IN_YAML,
            detail: "step '#{step_name}' not found in template YAML"
          )]
        )
        next
      end

      result_schema = step['result_schema']
      if result_schema.nil?
        results << SchemaComparisonResult.new(
          template_file: mapping.yaml_file,
          schema_location: "step:#{step_name}.result_schema",
          model_name: model_cls.name,
          mismatches: [FieldMismatch.new(
            field_name: '<schema>',
            kind: MismatchKind::FIELD_MISSING_IN_YAML,
            detail: 'no result_schema declared in template YAML'
          )]
        )
        next
      end

      yaml_norm = normalize_yaml_schema(result_schema)
      code_norm = normalize_dry_struct(model_cls)
      mismatches = compare_schemas(yaml_norm, code_norm)
      results << SchemaComparisonResult.new(
        template_file: mapping.yaml_file,
        schema_location: "step:#{step_name}.result_schema",
        model_name: model_cls.name,
        mismatches: mismatches
      )
    end

    results
  end

  def self.check_all(template_filter: nil)
    all_results = []
    SCHEMA_REGISTRY.each do |mapping|
      next if template_filter && !mapping.yaml_file.start_with?(template_filter)

      all_results.concat(check_template(mapping))
    end
    all_results
  end

  # ---------------------------------------------------------------------------
  # Output formatting
  # ---------------------------------------------------------------------------

  KIND_SYMBOLS = {
    MismatchKind::FIELD_MISSING_IN_CODE => '- CODE',
    MismatchKind::FIELD_MISSING_IN_YAML => '- YAML',
    MismatchKind::TYPE_MISMATCH         => '~ TYPE',
    MismatchKind::REQUIRED_MISMATCH     => '~ REQ '
  }.freeze

  def self.print_report(results, verbose: false)
    total_schemas = results.size
    failed_schemas = results.reject(&:ok?)

    if failed_schemas.empty?
      puts "All #{total_schemas} schemas consistent."
      return 0
    end

    # Group by template file
    by_file = results.group_by(&:template_file)

    by_file.each do |template_file, file_results|
      file_fails = file_results.reject(&:ok?)
      next if file_fails.empty? && !verbose

      puts "\n#{template_file}"
      file_results.each do |r|
        status = r.ok? ? 'OK' : 'MISMATCH'
        count = r.ok? ? '' : " (#{r.mismatches.size} issues)"
        puts "  #{status} #{r.schema_location} <-> #{r.model_name}#{count}"

        next unless !r.ok? || verbose

        r.mismatches.each do |m|
          symbol = KIND_SYMBOLS[m.kind] || '?'
          puts "    #{symbol}  #{m.field_name}: #{m.detail}"
        end
      end
    end

    ok_count = total_schemas - failed_schemas.size
    puts "\n#{ok_count}/#{total_schemas} schemas consistent, #{failed_schemas.size} with mismatches."
    failed_schemas.size
  end
end

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __FILE__ == $PROGRAM_NAME
  options = { verbose: false, template: nil }

  OptionParser.new do |opts|
    opts.banner = 'Usage: bundle exec ruby tools/schema_check.rb [options]'
    opts.on('-v', '--verbose', 'Show all schemas, not just failures') { options[:verbose] = true }
    opts.on('-t', '--template PREFIX', 'Filter to a single template by filename prefix') { |t| options[:template] = t }
  end.parse!

  results = SchemaCheck.check_all(template_filter: options[:template])
  fail_count = SchemaCheck.print_report(results, verbose: options[:verbose])
  exit(fail_count.positive? ? 1 : 0)
end
