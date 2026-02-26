/**
 * Microservices user registration step handlers.
 *
 * 5 steps forming a diamond dependency pattern:
 *   CreateUserAccount
 *        |-- SetupBillingProfile  --|
 *        |-- InitializePreferences -|
 *                                    |-- SendWelcomeSequence -> UpdateUserStatus
 *
 * Thin DSL wrappers that delegate to ../services/microservices for business logic.
 */

import { defineHandler, PermanentError } from "@tasker-systems/tasker";
import * as svc from "../services/microservices";
import {
	CreateUserAccountInputSchema,
	type MicroservicesCreateUserResult,
	type MicroservicesInitPreferencesResult,
	type MicroservicesSendWelcomeResult,
	type MicroservicesSetupBillingResult,
} from "../services/schemas";

export const CreateUserHandler = defineHandler(
	"Microservices.StepHandlers.CreateUserHandler",
	{
		inputs: {
			email: "email",
			username: "username",
			plan: "plan",
			metadata: "metadata",
		},
	},
	async ({ email, username, plan, metadata }) => {
		const parsed = CreateUserAccountInputSchema.safeParse({
			email,
			username,
			plan: plan || undefined,
			metadata: metadata || undefined,
		});

		if (!parsed.success) {
			const fields = parsed.error.issues
				.map((i) => i.path.join("."))
				.join(", ");
			throw new PermanentError(
				`Input validation failed: ${fields} — ${parsed.error.issues.map((i) => i.message).join("; ")}`,
			);
		}

		return svc.createUserAccount(parsed.data);
	},
);

export const SetupBillingHandler = defineHandler(
	"Microservices.StepHandlers.SetupBillingHandler",
	{ depends: { userData: "create_user_account" } },
	async ({ userData }) =>
		svc.setupBilling(userData as MicroservicesCreateUserResult),
);

export const InitPreferencesHandler = defineHandler(
	"Microservices.StepHandlers.InitPreferencesHandler",
	{
		depends: { userData: "create_user_account" },
		inputs: { metadata: "metadata" },
	},
	async ({ userData, metadata }) =>
		svc.initPreferences(
			userData as MicroservicesCreateUserResult,
			metadata as Record<string, unknown> | undefined,
		),
);

export const SendWelcomeHandler = defineHandler(
	"Microservices.StepHandlers.SendWelcomeHandler",
	{
		depends: {
			userData: "create_user_account",
			billingData: "setup_billing_profile",
			preferencesData: "initialize_preferences",
		},
	},
	async ({ userData, billingData, preferencesData }) =>
		svc.sendWelcome(
			userData as MicroservicesCreateUserResult,
			billingData as MicroservicesSetupBillingResult,
			preferencesData as MicroservicesInitPreferencesResult,
		),
);

export const UpdateStatusHandler = defineHandler(
	"Microservices.StepHandlers.UpdateStatusHandler",
	{
		depends: {
			userData: "create_user_account",
			billingData: "setup_billing_profile",
			preferencesData: "initialize_preferences",
			welcomeData: "send_welcome_sequence",
		},
	},
	async ({ userData, billingData, preferencesData, welcomeData }) =>
		svc.updateStatus(
			userData as MicroservicesCreateUserResult,
			billingData as MicroservicesSetupBillingResult,
			preferencesData as MicroservicesInitPreferencesResult,
			welcomeData as MicroservicesSendWelcomeResult,
		),
);
