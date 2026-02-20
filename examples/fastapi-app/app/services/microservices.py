"""Microservices user registration business logic.

Pure functions that create user accounts, set up billing profiles,
initialize preferences, send welcome sequences, and update user status.
No Tasker types -- just plain dicts in, typed models out.

Diamond dependency pattern:
  CreateUserAccount
       |-- SetupBillingProfile  --|
       |-- InitializePreferences -|
                                   |-- SendWelcomeSequence -> UpdateUserStatus
"""

from __future__ import annotations

import hashlib
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from tasker_core.errors import PermanentError, RetryableError

from .types import (
    CreateUserAccountInput,
    MicroservicesCreateUserResult,
    MicroservicesInitPreferencesResult,
    MicroservicesSendWelcomeResult,
    MicroservicesSetupBillingResult,
    MicroservicesUpdateStatusResult,
)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

RESERVED_USERNAMES = {"admin", "root", "system", "support", "test"}

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


# ---------------------------------------------------------------------------
# Service functions
# ---------------------------------------------------------------------------


def create_user_account(
    input: CreateUserAccountInput,
) -> MicroservicesCreateUserResult:
    """Validate user input, generate a unique user ID, and create the initial account."""
    email = input.email
    username = input.username
    plan = input.plan or "starter"
    referral_code = input.referral_code

    # Fields guaranteed non-None by @model_validator (raises PermanentError if missing)
    assert email is not None
    assert username is not None

    if "@" not in email:
        raise PermanentError(f"Invalid email address: {email}")

    full_name = username
    if len(full_name.strip()) < 2:
        raise PermanentError("Name must be at least 2 characters")

    if username.lower() in RESERVED_USERNAMES:
        raise PermanentError(f"Username '{username}' is reserved")

    internal_id = f"usr_{uuid.uuid4().hex[:12]}"
    derived_username = email.split("@")[0].lower()
    user_id = username or derived_username
    verification_token = hashlib.sha256(
        f"{internal_id}:{email}:{datetime.now(timezone.utc).isoformat()}".encode()
    ).hexdigest()[:32]

    return MicroservicesCreateUserResult(
        user_id=user_id,
        email=email,
        name=full_name,
        plan=plan,
        phone=None,
        source="web",
        status="created",
        internal_id=internal_id,
        username=derived_username,
        full_name=full_name,
        referral_code=referral_code,
        verification_token=verification_token,
        email_verified=False,
        account_status="pending_verification",
        created_at=datetime.now(timezone.utc).isoformat(),
    )


def setup_billing_profile(
    user_data: MicroservicesCreateUserResult,
) -> MicroservicesSetupBillingResult:
    """Configure plan-specific billing tiers with pricing and features."""
    if user_data is None:
        raise PermanentError("Missing create_user_account dependency")

    user_id = user_data.user_id
    plan = user_data.plan or "starter"
    internal_id = user_data.internal_id

    pricing = PLAN_PRICING.get(plan, PLAN_PRICING["starter"])
    limits = PLAN_LIMITS.get(plan, PLAN_LIMITS["starter"])
    billing_required = pricing["monthly_price"] > 0

    billing_id = f"bill_{uuid.uuid4().hex[:12]}"
    subscription_id = f"sub_{uuid.uuid4().hex[:12]}"

    trial_end = None
    next_billing_date = None
    if pricing["trial_days"] > 0:
        trial_end = (
            datetime.now(timezone.utc) + timedelta(days=pricing["trial_days"])
        ).isoformat()

    if billing_required:
        next_billing_date = (
            datetime.now(timezone.utc) + timedelta(days=30)
        ).isoformat()

    now = datetime.now(timezone.utc).isoformat()

    return MicroservicesSetupBillingResult(
        billing_id=billing_id,
        user_id=user_id,
        plan=plan,
        price=pricing["monthly_price"],
        currency="USD",
        billing_cycle="monthly",
        features=list(limits.keys()),
        status="active" if billing_required else "skipped_free_plan",
        billing_required=billing_required,
        next_billing_date=next_billing_date,
        subscription_id=subscription_id,
        user_internal_id=internal_id,
        pricing=pricing,
        limits=limits,
        billing_status="trial" if trial_end else "active",
        trial_end=trial_end,
        payment_method_required=billing_required,
        created_at=now,
    )


def initialize_preferences(
    user_data: MicroservicesCreateUserResult,
    custom_prefs: dict[str, Any] | None,
) -> MicroservicesInitPreferencesResult:
    """Initialize user preferences with plan-appropriate defaults."""
    if user_data is None:
        raise PermanentError("Missing create_user_account dependency")

    user_id = user_data.user_id
    plan = user_data.plan or "starter"
    internal_id = user_data.internal_id
    custom_prefs = custom_prefs or {}

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

    default_prefs = {**notifications, **ui_settings}
    preferences = {**default_prefs, **custom_prefs}

    preferences_id = f"pref_{uuid.uuid4().hex[:12]}"
    now = datetime.now(timezone.utc).isoformat()

    return MicroservicesInitPreferencesResult(
        preferences_id=preferences_id,
        user_id=user_id,
        plan=plan,
        preferences=preferences,
        defaults_applied=len(default_prefs),
        customizations=len(custom_prefs),
        status="active",
        user_internal_id=internal_id,
        notifications=notifications,
        ui_settings=ui_settings,
        feature_flags=feature_flags,
        onboarding_completed=False,
        created_at=now,
        updated_at=now,
    )


def send_welcome_sequence(
    user_data: MicroservicesCreateUserResult,
    billing_data: MicroservicesSetupBillingResult,
    prefs_data: MicroservicesInitPreferencesResult,
) -> MicroservicesSendWelcomeResult:
    """Send a multi-channel welcome sequence to the new user."""
    if not all([user_data, billing_data, prefs_data]):
        raise PermanentError("Missing upstream dependency results")

    user_id = user_data.user_id
    email = user_data.email
    plan = user_data.plan or "starter"
    full_name = user_data.full_name or user_data.name
    verification_token = user_data.verification_token
    trial_end = billing_data.trial_end
    prefs = prefs_data.preferences or {}

    messages_sent_list: list[dict[str, Any]] = []

    # Welcome email (if email notifications enabled)
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

    return MicroservicesSendWelcomeResult(
        user_id=user_id,
        plan=plan,
        channels_used=channels_used,
        messages_sent=len(messages_sent_list),
        welcome_sequence_id=welcome_sequence_id,
        status="sent",
        messages_sent_details=messages_sent_list,
        total_messages=len(messages_sent_list),
        sequence_id=f"seq_{uuid.uuid4().hex[:12]}",
        sent_at=now,
    )


def update_user_status(
    user_data: MicroservicesCreateUserResult,
    billing_data: MicroservicesSetupBillingResult,
    preferences_data: MicroservicesInitPreferencesResult,
    welcome_data: MicroservicesSendWelcomeResult,
) -> MicroservicesUpdateStatusResult:
    """Finalize user registration by activating the account."""
    if not all([user_data, billing_data, preferences_data, welcome_data]):
        raise PermanentError("Missing upstream dependency results")

    user_id = user_data.user_id
    plan = user_data.plan or "starter"
    email = user_data.email
    internal_id = user_data.internal_id
    billing_id = billing_data.billing_id
    subscription_id = billing_data.subscription_id
    messages_sent = welcome_data.total_messages if welcome_data.total_messages is not None else (welcome_data.messages_sent or 0)

    registration_summary: dict[str, Any] = {
        "user_id": user_id,
        "email": email,
        "plan": plan,
        "registration_status": "complete",
    }
    if plan != "starter" and billing_data.billing_id:
        registration_summary["billing_id"] = billing_data.billing_id
        registration_summary["next_billing_date"] = billing_data.next_billing_date
    prefs = preferences_data.preferences or {}
    registration_summary["preferences_count"] = len(prefs) if isinstance(prefs, dict) else 0
    registration_summary["welcome_sent"] = True
    registration_summary["notification_channels"] = welcome_data.channels_used or []
    registration_summary["user_created_at"] = user_data.created_at
    registration_summary["registration_completed_at"] = datetime.now(timezone.utc).isoformat()

    now = datetime.now(timezone.utc).isoformat()

    return MicroservicesUpdateStatusResult(
        user_id=user_id,
        status="active",
        plan=plan,
        registration_summary=registration_summary,
        activation_timestamp=now,
        all_services_coordinated=True,
        services_completed=[
            "user_service",
            "billing_service",
            "preferences_service",
            "notification_service",
        ],
        internal_id=internal_id,
        email=email,
        account_status="active",
        billing_id=billing_id,
        subscription_id=subscription_id,
        onboarding_status="in_progress",
        welcome_messages_sent=messages_sent,
        registration_complete=True,
        activated_at=now,
    )
