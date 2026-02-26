/**
 * Customer Success namespace step handlers for refund processing.
 *
 * 5 sequential steps owned by the Customer Success team:
 *   ValidateRefundRequest -> CheckRefundEligibility -> CalculateRefundAmount
 *       -> NotifyCustomerSuccess -> UpdateCrmRecord
 *
 * Thin DSL wrappers that delegate to ../services/customer-success for business logic.
 */

import { defineHandler, PermanentError } from "@tasker-systems/tasker";
import * as svc from "../services/customer-success";
import {
	type CustomerSuccessApproveRefundResult,
	type CustomerSuccessCheckRefundPolicyResult,
	type CustomerSuccessExecuteRefundResult,
	type CustomerSuccessValidateRefundResult,
	ValidateRefundRequestInputSchema,
} from "../services/schemas";

export const ValidateRefundRequestHandler = defineHandler(
	"CustomerSuccess.StepHandlers.ValidateRefundRequestHandler",
	{
		inputs: {
			ticketId: "ticket_id",
			customerId: "customer_id",
			refundAmount: "refund_amount",
			refundReason: "refund_reason",
		},
	},
	async ({ ticketId, customerId, refundAmount, refundReason }) => {
		const parsed = ValidateRefundRequestInputSchema.safeParse({
			ticketId,
			customerId,
			refundAmount,
			refundReason: refundReason || "customer_request",
		});

		if (!parsed.success) {
			const fields = parsed.error.issues
				.map((i) => i.path.join("."))
				.join(", ");
			throw new PermanentError(
				`Input validation failed: ${fields} — ${parsed.error.issues.map((i) => i.message).join("; ")}`,
			);
		}

		return svc.validateRefundRequest(parsed.data);
	},
);

export const CheckRefundEligibilityHandler = defineHandler(
	"CustomerSuccess.StepHandlers.CheckRefundEligibilityHandler",
	{
		depends: { validationResult: "validate_refund_request" },
		inputs: { refundAmount: "refund_amount" },
	},
	async ({ validationResult, refundAmount }) =>
		svc.checkRefundEligibility(
			validationResult as CustomerSuccessValidateRefundResult,
			refundAmount as number | undefined,
		),
);

export const CalculateRefundAmountHandler = defineHandler(
	"CustomerSuccess.StepHandlers.CalculateRefundAmountHandler",
	{
		depends: {
			policyResult: "check_refund_policy",
			validationResult: "validate_refund_request",
		},
	},
	async ({ policyResult, validationResult }) =>
		svc.calculateRefundAmount(
			policyResult as CustomerSuccessCheckRefundPolicyResult,
			(validationResult as CustomerSuccessValidateRefundResult)?.customer_id,
		),
);

export const NotifyCustomerSuccessHandler = defineHandler(
	"CustomerSuccess.StepHandlers.NotifyCustomerSuccessHandler",
	{
		depends: {
			approvalResult: "get_manager_approval",
			validationResult: "validate_refund_request",
		},
		inputs: { correlationId: "correlation_id" },
	},
	async ({ approvalResult, validationResult, correlationId }) =>
		svc.notifyCustomerSuccess(
			approvalResult as CustomerSuccessApproveRefundResult,
			validationResult as CustomerSuccessValidateRefundResult,
			correlationId as string | undefined,
		),
);

export const UpdateCrmRecordHandler = defineHandler(
	"CustomerSuccess.StepHandlers.UpdateCrmRecordHandler",
	{
		depends: {
			delegationResult: "execute_refund_workflow",
			validationResult: "validate_refund_request",
		},
		inputs: { refundAmount: "refund_amount" },
	},
	async ({ delegationResult, validationResult, refundAmount }) =>
		svc.updateCrmRecord(
			delegationResult as CustomerSuccessExecuteRefundResult,
			validationResult as CustomerSuccessValidateRefundResult,
			refundAmount as number | undefined,
		),
);
