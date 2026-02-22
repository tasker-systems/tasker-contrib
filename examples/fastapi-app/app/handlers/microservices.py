"""Microservices user registration step handlers.

5 steps forming a diamond dependency pattern:
  CreateUserAccount
       |-- SetupBillingProfile  --|
       |-- InitializePreferences -|
                                   |-- SendWelcomeSequence -> UpdateUserStatus

Thin DSL wrappers that delegate to app.services.microservices for business logic.
"""

from __future__ import annotations

from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from tasker_core.types import StepContext

from app.services import microservices as svc
from app.services.types import (
    CreateUserAccountInput,
    MicroservicesCreateUserResult,
    MicroservicesInitPreferencesResult,
    MicroservicesSendWelcomeResult,
    MicroservicesSetupBillingResult,
)


@step_handler("create_user_account")
@inputs(CreateUserAccountInput)
def create_user_account(inputs: CreateUserAccountInput, context: StepContext):
    # Input validation (required fields) is handled by the model's
    # @model_validator — see CreateUserAccountInput in app/services/types.py.
    return svc.create_user_account(inputs)


@step_handler("setup_billing_profile")
@depends_on(user_data=("create_user_account", MicroservicesCreateUserResult))
def setup_billing_profile(user_data: MicroservicesCreateUserResult, context: StepContext):
    return svc.setup_billing_profile(user_data=user_data)


@step_handler("initialize_preferences")
@depends_on(user_data=("create_user_account", MicroservicesCreateUserResult))
@inputs(CreateUserAccountInput)
def initialize_preferences(
    user_data: MicroservicesCreateUserResult,
    inputs: CreateUserAccountInput,
    context: StepContext,
):
    return svc.initialize_preferences(user_data=user_data, custom_prefs=inputs.preferences)


@step_handler("send_welcome_sequence")
@depends_on(
    user_data=("create_user_account", MicroservicesCreateUserResult),
    billing_data=("setup_billing_profile", MicroservicesSetupBillingResult),
    prefs_data=("initialize_preferences", MicroservicesInitPreferencesResult),
)
def send_welcome_sequence(
    user_data: MicroservicesCreateUserResult,
    billing_data: MicroservicesSetupBillingResult,
    prefs_data: MicroservicesInitPreferencesResult,
    context: StepContext,
):
    return svc.send_welcome_sequence(
        user_data=user_data, billing_data=billing_data, prefs_data=prefs_data
    )


@step_handler("update_user_status")
@depends_on(
    user_data=("create_user_account", MicroservicesCreateUserResult),
    billing_data=("setup_billing_profile", MicroservicesSetupBillingResult),
    preferences_data=("initialize_preferences", MicroservicesInitPreferencesResult),
    welcome_data=("send_welcome_sequence", MicroservicesSendWelcomeResult),
)
def update_user_status(
    user_data: MicroservicesCreateUserResult,
    billing_data: MicroservicesSetupBillingResult,
    preferences_data: MicroservicesInitPreferencesResult,
    welcome_data: MicroservicesSendWelcomeResult,
    context: StepContext,
):
    return svc.update_user_status(
        user_data=user_data,
        billing_data=billing_data,
        preferences_data=preferences_data,
        welcome_data=welcome_data,
    )
