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
        user_info = context.get_input("user_info") or {}

        email = user_info.get("email")
        name = user_info.get("name")
        full_name = name  # App uses full_name internally
        plan = user_info.get("plan", "starter")
        phone = user_info.get("phone")
        source = user_info.get("source", "web")
        user_id_input = user_info.get("user_id")

        if not email or "@" not in email:
            return StepHandlerResult.failure(
                message=f"Invalid email address: {email}",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_EMAIL",
            )

        if not name or len(name.strip()) < 2:
            return StepHandlerResult.failure(
                message="Name must be at least 2 characters",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="INVALID_NAME",
            )

        if user_id_input and user_id_input.lower() in self.RESERVED_USERNAMES:
            return StepHandlerResult.failure(
                message=f"Username '{user_id_input}' is reserved",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="RESERVED_USERNAME",
            )

        internal_id = f"usr_{uuid.uuid4().hex[:12]}"
        username = email.split("@")[0].lower()
        user_id = user_id_input or username
        verification_token = hashlib.sha256(
            f"{internal_id}:{email}:{datetime.now(timezone.utc).isoformat()}".encode()
        ).hexdigest()[:32]

        return StepHandlerResult.success(
            result={
                "user_id": user_id,
                "email": email,
                "name": name,
                "plan": plan,
                "phone": phone,
                "source": source,
                "status": "created",
                "internal_id": internal_id,
                "username": username,
                "full_name": full_name,
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

        user_id = context.get_dependency_field("create_user_account", "user_id")
        plan = context.get_dependency_field("create_user_account", "plan") or "starter"
        internal_id = user_data.get("internal_id")

        pricing = self.PLAN_PRICING.get(plan, self.PLAN_PRICING["starter"])
        limits = self.PLAN_LIMITS.get(plan, self.PLAN_LIMITS["starter"])
        billing_required = pricing["monthly_price"] > 0

        billing_id = f"bill_{uuid.uuid4().hex[:12]}"
        subscription_id = f"sub_{uuid.uuid4().hex[:12]}"

        trial_end = None
        next_billing_date = None
        if pricing["trial_days"] > 0:
            from datetime import timedelta

            trial_end = (
                datetime.now(timezone.utc) + timedelta(days=pricing["trial_days"])
            ).isoformat()

        if billing_required:
            from datetime import timedelta

            next_billing_date = (
                datetime.now(timezone.utc) + timedelta(days=30)
            ).isoformat()

        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "billing_id": billing_id,
                "user_id": user_id,
                "plan": plan,
                "price": pricing["monthly_price"],
                "currency": "USD",
                "billing_cycle": "monthly",
                "features": list(limits.keys()),
                "status": "active" if billing_required else "skipped_free_plan",
                "billing_required": billing_required,
                "next_billing_date": next_billing_date,
                "subscription_id": subscription_id,
                "user_internal_id": internal_id,
                "pricing": pricing,
                "limits": limits,
                "billing_status": "trial" if trial_end else "active",
                "trial_end": trial_end,
                "payment_method_required": billing_required,
                "created_at": now,
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

        user_id = context.get_dependency_field("create_user_account", "user_id")
        plan = context.get_dependency_field("create_user_account", "plan") or "starter"
        internal_id = user_data.get("internal_id")

        # Source-aligned: read user_info from task context for custom preferences
        user_info = context.get_input("user_info") or {}
        custom_prefs = user_info.get("preferences", {})

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

        # Build combined preferences dict (source-aligned)
        default_prefs = {**notifications, **ui_settings}
        preferences = {**default_prefs, **custom_prefs}

        preferences_id = f"pref_{uuid.uuid4().hex[:12]}"
        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "preferences_id": preferences_id,
                "user_id": user_id,
                "plan": plan,
                "preferences": preferences,
                "defaults_applied": len(default_prefs),
                "customizations": len(custom_prefs),
                "status": "active",
                "user_internal_id": internal_id,
                "notifications": notifications,
                "ui_settings": ui_settings,
                "feature_flags": feature_flags,
                "onboarding_completed": False,
                "created_at": now,
                "updated_at": now,
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

        # Source-aligned: use get_dependency_field for nested extraction
        user_id = context.get_dependency_field("create_user_account", "user_id")
        email = context.get_dependency_field("create_user_account", "email")
        plan = context.get_dependency_field("create_user_account", "plan") or "starter"

        full_name = user_data.get("full_name") or user_data.get("name")
        verification_token = user_data.get("verification_token")
        trial_end = billing_data.get("trial_end")

        # Source-aligned: read preferences from preferences_data
        prefs = prefs_data.get("preferences", {})

        messages_sent_list: list[dict[str, Any]] = []

        # Welcome email (if email_notifications enabled)
        if prefs.get("email_updates", True) or prefs.get("email_notifications", True):
            welcome_msg_id = f"msg_{uuid.uuid4().hex[:16]}"
            messages_sent_list.append(
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
        messages_sent_list.append(
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
        messages_sent_list.append(
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
            messages_sent_list.append(
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

        channels_used = list({m["channel"] for m in messages_sent_list})
        welcome_sequence_id = f"welcome_{uuid.uuid4().hex[:12]}"
        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "user_id": user_id,
                "plan": plan,
                "channels_used": channels_used,
                "messages_sent": len(messages_sent_list),
                "welcome_sequence_id": welcome_sequence_id,
                "status": "sent",
                "messages_sent_details": messages_sent_list,
                "total_messages": len(messages_sent_list),
                "sequence_id": f"seq_{uuid.uuid4().hex[:12]}",
                "sent_at": now,
            },
            metadata={"channels": len(channels_used)},
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
        preferences_data = context.get_dependency_result("initialize_preferences")
        welcome_data = context.get_dependency_result("send_welcome_sequence")

        if not all([user_data, billing_data, preferences_data, welcome_data]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        # Source-aligned: use get_dependency_field for nested extraction
        user_id = context.get_dependency_field("create_user_account", "user_id")
        plan = context.get_dependency_field("create_user_account", "plan") or "starter"
        email = context.get_dependency_field("create_user_account", "email")

        internal_id = user_data.get("internal_id")
        billing_id = billing_data.get("billing_id")
        subscription_id = billing_data.get("subscription_id")
        messages_sent = welcome_data.get("total_messages", welcome_data.get("messages_sent", 0))

        # Source-aligned: build registration_summary
        registration_summary = {
            "user_id": user_id,
            "email": email,
            "plan": plan,
            "registration_status": "complete",
        }
        if plan != "starter" and billing_data.get("billing_id"):
            registration_summary["billing_id"] = billing_data.get("billing_id")
            registration_summary["next_billing_date"] = billing_data.get("next_billing_date")
        prefs = preferences_data.get("preferences", {})
        registration_summary["preferences_count"] = len(prefs) if isinstance(prefs, dict) else 0
        registration_summary["welcome_sent"] = True
        registration_summary["notification_channels"] = welcome_data.get("channels_used", [])
        registration_summary["user_created_at"] = user_data.get("created_at")
        registration_summary["registration_completed_at"] = datetime.now(timezone.utc).isoformat()

        now = datetime.now(timezone.utc).isoformat()

        return StepHandlerResult.success(
            result={
                "user_id": user_id,
                "status": "active",
                "plan": plan,
                "registration_summary": registration_summary,
                "activation_timestamp": now,
                "all_services_coordinated": True,
                "services_completed": [
                    "user_service",
                    "billing_service",
                    "preferences_service",
                    "notification_service",
                ],
                "internal_id": internal_id,
                "email": email,
                "account_status": "active",
                "billing_id": billing_id,
                "subscription_id": subscription_id,
                "onboarding_status": "in_progress",
                "welcome_messages_sent": messages_sent,
                "registration_complete": True,
                "activated_at": now,
            },
            metadata={
                "registration_steps_completed": 5,
                "plan": plan,
            },
        )
