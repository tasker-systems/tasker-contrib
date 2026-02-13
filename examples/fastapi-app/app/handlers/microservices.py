"""Microservices user registration step handlers.

5 steps forming a diamond dependency pattern:
  CreateUserAccount
       ├──> SetupBillingProfile  ──┐
       └──> InitializePreferences ─┤
                                    └──> SendWelcomeSequence -> UpdateUserStatus

The diamond pattern demonstrates two parallel branches that converge
before the final steps execute.
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timezone
from typing import Any

from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class CreateUserAccountHandler(StepHandler):
    """Create the core user account.

    Validates user input, generates a unique user ID, and creates the
    initial account record. This is the root of the diamond pattern --
    both billing and preferences depend on this step.
    """

    handler_name = "create_user_account"
    handler_version = "1.0.0"

    RESERVED_USERNAMES = {"admin", "root", "system", "support", "test"}

    def call(self, context: StepContext) -> StepHandlerResult:
        email = context.get_input("email")
        full_name = context.get_input("full_name")
        user_id = context.get_input("user_id")
        plan = context.get_input("plan") or "starter"

        if not email or "@" not in email:
            return StepHandlerResult.failure(
                message=f"Invalid email address: {email}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_EMAIL",
            )

        if not full_name or len(full_name.strip()) < 2:
            return StepHandlerResult.failure(
                message="Full name must be at least 2 characters",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_NAME",
            )

        if user_id and user_id.lower() in self.RESERVED_USERNAMES:
            return StepHandlerResult.failure(
                message=f"Username '{user_id}' is reserved",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="RESERVED_USERNAME",
            )

        internal_id = f"usr_{uuid.uuid4().hex[:12]}"
        username = email.split("@")[0].lower()
        verification_token = hashlib.sha256(
            f"{internal_id}:{email}:{datetime.now(timezone.utc).isoformat()}".encode()
        ).hexdigest()[:32]

        return StepHandlerResult.success(
            result={
                "internal_id": internal_id,
                "user_id": user_id or username,
                "username": username,
                "email": email,
                "full_name": full_name,
                "plan": plan,
                "verification_token": verification_token,
                "email_verified": False,
                "account_status": "pending_verification",
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"plan_selected": plan},
        )


class SetupBillingProfileHandler(StepHandler):
    """Set up the billing profile based on the selected plan.

    Reads the user account from create_user_account and configures
    plan-specific billing tiers with pricing and features.
    """

    handler_name = "setup_billing_profile"
    handler_version = "1.0.0"

    PLAN_PRICING = {
        "starter": {"monthly_price": 0.0, "annual_price": 0.0, "trial_days": 0},
        "professional": {"monthly_price": 29.99, "annual_price": 299.99, "trial_days": 14},
        "enterprise": {"monthly_price": 99.99, "annual_price": 999.99, "trial_days": 30},
    }

    PLAN_LIMITS = {
        "starter": {"api_calls": 1000, "storage_gb": 1, "team_members": 1},
        "professional": {"api_calls": 50000, "storage_gb": 50, "team_members": 10},
        "enterprise": {"api_calls": -1, "storage_gb": 500, "team_members": -1},
    }

    def call(self, context: StepContext) -> StepHandlerResult:
        user_data = context.get_dependency_result("create_user_account")
        if user_data is None:
            return StepHandlerResult.failure(
                message="Missing create_user_account dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        plan = user_data.get("plan", "starter")
        internal_id = user_data.get("internal_id")

        pricing = self.PLAN_PRICING.get(plan, self.PLAN_PRICING["starter"])
        limits = self.PLAN_LIMITS.get(plan, self.PLAN_LIMITS["starter"])

        billing_id = f"bill_{uuid.uuid4().hex[:12]}"
        subscription_id = f"sub_{uuid.uuid4().hex[:12]}"

        trial_end = None
        if pricing["trial_days"] > 0:
            from datetime import timedelta

            trial_end = (
                datetime.now(timezone.utc) + timedelta(days=pricing["trial_days"])
            ).isoformat()

        return StepHandlerResult.success(
            result={
                "billing_id": billing_id,
                "subscription_id": subscription_id,
                "user_internal_id": internal_id,
                "plan": plan,
                "pricing": pricing,
                "limits": limits,
                "billing_status": "trial" if trial_end else "active",
                "trial_end": trial_end,
                "payment_method_required": pricing["monthly_price"] > 0,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"plan_tier": plan},
        )


class InitializePreferencesHandler(StepHandler):
    """Initialize user preferences with plan-appropriate defaults.

    Sets up notification preferences, UI settings, and feature flags
    based on the user's selected plan tier.
    """

    handler_name = "initialize_preferences"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        user_data = context.get_dependency_result("create_user_account")
        if user_data is None:
            return StepHandlerResult.failure(
                message="Missing create_user_account dependency",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        plan = user_data.get("plan", "starter")
        internal_id = user_data.get("internal_id")
        email = user_data.get("email")

        notifications = {
            "email_updates": True,
            "marketing_emails": plan != "enterprise",
            "weekly_digest": True,
            "security_alerts": True,
            "product_updates": True,
            "billing_alerts": plan != "starter",
        }

        ui_settings = {
            "theme": "light",
            "language": "en",
            "timezone": "UTC",
            "date_format": "YYYY-MM-DD",
            "items_per_page": 25,
            "sidebar_collapsed": False,
        }

        feature_flags = {
            "beta_features": plan == "enterprise",
            "advanced_analytics": plan in ("professional", "enterprise"),
            "api_access": plan in ("professional", "enterprise"),
            "custom_integrations": plan == "enterprise",
            "priority_support": plan == "enterprise",
            "export_data": True,
        }

        preferences_id = f"pref_{uuid.uuid4().hex[:12]}"

        return StepHandlerResult.success(
            result={
                "preferences_id": preferences_id,
                "user_internal_id": internal_id,
                "notifications": notifications,
                "ui_settings": ui_settings,
                "feature_flags": feature_flags,
                "onboarding_completed": False,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"defaults_based_on_plan": plan},
        )


class SendWelcomeSequenceHandler(StepHandler):
    """Send a multi-channel welcome sequence to the new user.

    Reads user, billing, and preferences data to compose personalized
    welcome messages across email, in-app, and optional SMS channels.
    """

    handler_name = "send_welcome_sequence"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        user_data = context.get_dependency_result("create_user_account")
        billing_data = context.get_dependency_result("setup_billing_profile")
        prefs_data = context.get_dependency_result("initialize_preferences")

        if not all([user_data, billing_data, prefs_data]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        email = user_data.get("email")
        full_name = user_data.get("full_name")
        plan = user_data.get("plan", "starter")
        verification_token = user_data.get("verification_token")
        trial_end = billing_data.get("trial_end")

        messages_sent: list[dict[str, Any]] = []

        # Welcome email
        welcome_msg_id = f"msg_{uuid.uuid4().hex[:16]}"
        messages_sent.append(
            {
                "message_id": welcome_msg_id,
                "channel": "email",
                "recipient": email,
                "template": "welcome_email_v3",
                "subject": f"Welcome to Tasker, {full_name}!",
                "status": "sent",
            }
        )

        # Verification email
        verify_msg_id = f"msg_{uuid.uuid4().hex[:16]}"
        messages_sent.append(
            {
                "message_id": verify_msg_id,
                "channel": "email",
                "recipient": email,
                "template": "email_verification",
                "subject": "Verify your email address",
                "verification_link": f"https://app.example.com/verify/{verification_token}",
                "status": "sent",
            }
        )

        # In-app onboarding
        onboard_msg_id = f"msg_{uuid.uuid4().hex[:16]}"
        messages_sent.append(
            {
                "message_id": onboard_msg_id,
                "channel": "in_app",
                "template": "onboarding_tour",
                "status": "queued",
            }
        )

        # Trial notification if applicable
        if trial_end:
            trial_msg_id = f"msg_{uuid.uuid4().hex[:16]}"
            messages_sent.append(
                {
                    "message_id": trial_msg_id,
                    "channel": "email",
                    "recipient": email,
                    "template": "trial_started",
                    "subject": f"Your {plan} trial has started",
                    "trial_end": trial_end,
                    "status": "sent",
                }
            )

        return StepHandlerResult.success(
            result={
                "messages_sent": messages_sent,
                "total_messages": len(messages_sent),
                "channels_used": list({m["channel"] for m in messages_sent}),
                "sequence_id": f"seq_{uuid.uuid4().hex[:12]}",
                "sent_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"channels": len({m["channel"] for m in messages_sent})},
        )


class UpdateUserStatusHandler(StepHandler):
    """Finalize user registration by activating the account.

    Aggregates all upstream results and transitions the user account
    from pending to active status.
    """

    handler_name = "update_user_status"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        user_data = context.get_dependency_result("create_user_account")
        billing_data = context.get_dependency_result("setup_billing_profile")
        welcome_data = context.get_dependency_result("send_welcome_sequence")

        if not all([user_data, billing_data, welcome_data]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        internal_id = user_data.get("internal_id")
        email = user_data.get("email")
        plan = user_data.get("plan", "starter")
        billing_id = billing_data.get("billing_id")
        subscription_id = billing_data.get("subscription_id")
        messages_sent = welcome_data.get("total_messages", 0)

        return StepHandlerResult.success(
            result={
                "internal_id": internal_id,
                "email": email,
                "plan": plan,
                "account_status": "active",
                "billing_id": billing_id,
                "subscription_id": subscription_id,
                "onboarding_status": "in_progress",
                "welcome_messages_sent": messages_sent,
                "registration_complete": True,
                "activated_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={
                "registration_steps_completed": 5,
                "plan": plan,
            },
        )
