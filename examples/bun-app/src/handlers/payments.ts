/**
 * Payments namespace step handlers for refund processing.
 *
 * 4 sequential steps owned by the Payments team:
 *   ProcessRefundPayment -> UpdateLedger -> ReconcileAccount -> GenerateRefundReceipt
 *
 * Thin DSL wrappers that delegate to ../services/payments for business logic.
 */

import { defineHandler, PermanentError } from "@tasker-systems/tasker";
import * as svc from "../services/payments";
import {
	type PaymentsProcessGatewayResult,
	type PaymentsValidateEligibilityResult,
	ValidatePaymentEligibilityInputSchema,
} from "../services/schemas";

export const ProcessRefundPaymentHandler = defineHandler(
	"Payments.StepHandlers.ProcessRefundPaymentHandler",
	{
		inputs: {
			paymentId: "payment_id",
			refundAmount: "refund_amount",
		},
	},
	async ({ paymentId, refundAmount }) => {
		const parsed = ValidatePaymentEligibilityInputSchema.safeParse({
			paymentId,
			refundAmount,
		});

		if (!parsed.success) {
			const fields = parsed.error.issues
				.map((i) => i.path.join("."))
				.join(", ");
			throw new PermanentError(
				`Input validation failed: ${fields} — ${parsed.error.issues.map((i) => i.message).join("; ")}`,
			);
		}

		return svc.validateEligibility(parsed.data);
	},
);

export const UpdateLedgerHandler = defineHandler(
	"Payments.StepHandlers.UpdateLedgerHandler",
	{
		depends: { validationResult: "validate_payment_eligibility" },
	},
	async ({ validationResult }) =>
		svc.processGateway(
			validationResult as PaymentsValidateEligibilityResult | undefined,
		),
);

export const ReconcileAccountHandler = defineHandler(
	"Payments.StepHandlers.ReconcileAccountHandler",
	{
		depends: { refundResult: "process_gateway_refund" },
	},
	async ({ refundResult }) =>
		svc.updateRecords(refundResult as PaymentsProcessGatewayResult | undefined),
);

export const GenerateRefundReceiptHandler = defineHandler(
	"Payments.StepHandlers.GenerateRefundReceiptHandler",
	{
		depends: { refundResult: "process_gateway_refund" },
		inputs: { customerEmail: "customer_email" },
	},
	async ({ refundResult, customerEmail }) =>
		svc.notifyCustomer(
			refundResult as PaymentsProcessGatewayResult | undefined,
			customerEmail as string | undefined,
		),
);
