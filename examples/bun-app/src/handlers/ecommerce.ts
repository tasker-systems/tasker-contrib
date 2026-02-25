/**
 * E-commerce order processing step handlers.
 *
 * 5 sequential steps demonstrating a linear pipeline:
 *   ValidateCart -> ProcessPayment -> UpdateInventory -> CreateOrder -> SendConfirmation
 *
 * Thin DSL wrappers that delegate to ../services/ecommerce for business logic.
 */

import { defineHandler } from "@tasker-systems/tasker";
import { z } from "zod";
import * as svc from "../services/ecommerce";
import type {
	EcommerceCreateOrderResult,
	EcommerceProcessPaymentResult,
	EcommerceUpdateInventoryResult,
	EcommerceValidateCartResult,
	PaymentInfo,
} from "../services/schemas";
import { CartItemSchema } from "../services/schemas";

export const ValidateCartHandler = defineHandler(
	"Ecommerce.StepHandlers.ValidateCartHandler",
	{ inputs: { cartItems: "cart_items" } },
	async ({ cartItems }) =>
		svc.validateCartItems(z.array(CartItemSchema).optional().parse(cartItems)),
);

export const ProcessPaymentHandler = defineHandler(
	"Ecommerce.StepHandlers.ProcessPaymentHandler",
	{
		depends: { cartResult: "validate_cart" },
		inputs: { paymentInfo: "payment_info" },
	},
	async ({ cartResult, paymentInfo }) =>
		svc.processPayment(
			cartResult as EcommerceValidateCartResult,
			paymentInfo as PaymentInfo | undefined,
		),
);

export const UpdateInventoryHandler = defineHandler(
	"Ecommerce.StepHandlers.UpdateInventoryHandler",
	{ depends: { cartResult: "validate_cart" } },
	async ({ cartResult }) =>
		svc.updateInventory(
			(cartResult as EcommerceValidateCartResult).validated_items,
		),
);

export const CreateOrderHandler = defineHandler(
	"Ecommerce.StepHandlers.CreateOrderHandler",
	{
		depends: {
			cartResult: "validate_cart",
			paymentResult: "process_payment",
			inventoryResult: "update_inventory",
		},
		inputs: { customerEmail: "customer_email" },
	},
	async ({ cartResult, paymentResult, inventoryResult, customerEmail }) =>
		svc.createOrder(
			cartResult as EcommerceValidateCartResult,
			paymentResult as EcommerceProcessPaymentResult,
			inventoryResult as EcommerceUpdateInventoryResult,
			customerEmail as string | undefined,
		),
);

export const SendConfirmationHandler = defineHandler(
	"Ecommerce.StepHandlers.SendConfirmationHandler",
	{
		depends: {
			orderResult: "create_order",
			cartResult: "validate_cart",
		},
		inputs: { customerEmail: "customer_email" },
	},
	async ({ orderResult, cartResult, customerEmail }) =>
		svc.sendConfirmation(
			orderResult as EcommerceCreateOrderResult,
			cartResult as EcommerceValidateCartResult | undefined,
			customerEmail as string | undefined,
		),
);
