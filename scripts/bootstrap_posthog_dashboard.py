#!/usr/bin/env python3
"""
Bootstrap GlanceSAT PostHog dashboards via API.

Requires a PostHog *personal* API key (not the phc_ project token):
  PostHog → Settings → Personal API keys → Create with scopes:
    - dashboard:write
    - insight:write
    - project:read

Usage:
  export POSTHOG_API_KEY="phx_..."
  export POSTHOG_PROJECT_ID="12345"   # Project Settings → Project ID
  python3 scripts/bootstrap_posthog_dashboard.py

Optional:
  export POSTHOG_HOST="https://us.posthog.com"   # default
  python3 scripts/bootstrap_posthog_dashboard.py --dry-run
  python3 scripts/bootstrap_posthog_dashboard.py --list-dashboards
  python3 scripts/bootstrap_posthog_dashboard.py --dashboard-id 1721650 --from-index 0 --count 6
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

DATE_RANGE = {"date_from": "-30d"}
APP_OPENED = "Application Opened"

HOST = os.environ.get("POSTHOG_HOST", "https://us.posthog.com").rstrip("/")
API_KEY = os.environ.get("POSTHOG_API_KEY", "")
PROJECT_ID = os.environ.get("POSTHOG_PROJECT_ID", "")


def event_node(
    event: str,
    name: str | None = None,
    *,
    math: str | None = "dau",
    properties: list[dict] | None = None,
) -> dict:
    node: dict = {
        "kind": "EventsNode",
        "event": event,
        "name": name or event,
    }
    if math is not None:
        node["math"] = math
    if properties:
        node["properties"] = properties
    return node


def stickiness_query(event: str, name: str | None = None) -> dict:
    return {
        "kind": "InsightVizNode",
        "source": {
            "kind": "StickinessQuery",
            "series": [event_node(event, name, math=None)],
            "dateRange": DATE_RANGE,
            "interval": "day",
        },
    }


def lifecycle_query(event: str, name: str | None = None) -> dict:
    return {
        "kind": "InsightVizNode",
        "source": {
            "kind": "LifecycleQuery",
            "series": [event_node(event, name, math=None)],
            "dateRange": DATE_RANGE,
            "interval": "day",
        },
    }


def prop_filter(key: str, value: str | bool) -> dict:
    return {
        "key": key,
        "value": value,
        "operator": "exact",
        "type": "event",
    }


def trends_query(series: list[dict], *, breakdown: str | None = None) -> dict:
    source: dict = {
        "kind": "TrendsQuery",
        "series": series,
        "dateRange": DATE_RANGE,
        "interval": "day",
    }
    if breakdown:
        source["breakdownFilter"] = {
            "breakdown": breakdown,
            "breakdown_type": "event",
        }
    return {"kind": "InsightVizNode", "source": source}


def funnel_query(
    steps: list[dict],
    *,
    window_days: int = 14,
) -> dict:
    return {
        "kind": "InsightVizNode",
        "source": {
            "kind": "FunnelsQuery",
            "series": steps,
            "dateRange": DATE_RANGE,
            "funnelsFilter": {
                "funnelWindowInterval": window_days,
                "funnelWindowIntervalUnit": "day",
            },
        },
    }


def retention_query(
    target_event: str,
    returning_event: str,
    *,
    period: str = "Day",
    total_intervals: int = 8,
) -> dict:
    return {
        "kind": "InsightVizNode",
        "source": {
            "kind": "RetentionQuery",
            "dateRange": DATE_RANGE,
            "retentionFilter": {
                "period": period,
                "totalIntervals": total_intervals,
                "targetEntity": {
                    "id": target_event,
                    "type": "events",
                },
                "returningEntity": {
                    "id": returning_event,
                    "type": "events",
                },
            },
        },
    }


ONBOARDING_STEPS = [
    "habits",
    "study_smart",
    "sat_date",
    "goals",
    "diagnostic",
    "reminder",
    "plan_preview",
    "paywall",
    "widget_install",
]


def onboarding_funnel_query() -> dict:
    steps = [event_node("onboarding_started", "Started")]
    for step in ONBOARDING_STEPS:
        steps.append(
            event_node(
                "onboarding_step_completed",
                step.replace("_", " ").title(),
                properties=[prop_filter("step_name", step)],
            )
        )
    steps.append(event_node("onboarding_completed", "Completed"))
    return funnel_query(steps, window_days=1)


INSIGHTS: list[dict] = [
    # Tier 1 — Core app health
    {
        "name": "DAU / MAU stickiness (app opens)",
        "description": "How many days per month users open the app. Target >20% on peak day for habit apps.",
        "query": stickiness_query(APP_OPENED, "Application Opened"),
    },
    {
        "name": "App opens: new vs returning",
        "description": "Top-of-funnel traffic split between first-time and returning openers.",
        "query": lifecycle_query(APP_OPENED, "Application Opened"),
    },
    {
        "name": "Notification → quiz conversion",
        "description": "Push tap to primary daily quiz start within 24h.",
        "query": funnel_query(
            [
                event_node("notification_tapped", "Notification tapped", math=None),
                event_node(
                    "daily_quiz_started",
                    "Primary quiz started",
                    math=None,
                    properties=[prop_filter("is_supplemental", False)],
                ),
            ],
            window_days=1,
        ),
    },
    # Tier 2 — Ed-tech north star
    {
        "name": "North star lifecycle funnel",
        "description": "App open → onboarding → primary quiz → subscription (executive view).",
        "query": funnel_query(
            [
                event_node(APP_OPENED, "App opened", math=None),
                event_node("onboarding_completed", "Onboarding done", math=None),
                event_node(
                    "daily_quiz_completed",
                    "Primary quiz done",
                    math=None,
                    properties=[prop_filter("is_supplemental", False)],
                ),
                event_node("subscription_completed", "Subscribed", math=None),
            ],
            window_days=30,
        ),
    },
    {
        "name": "Onboarding goals mix",
        "description": "Dream score selections from the goals step.",
        "query": trends_query(
            [event_node("onboarding_goals_selected", "Goals selected", math="total")],
            breakdown="dream_score",
        ),
    },
    {
        "name": "Diagnostic baseline mix",
        "description": "Calibration starting-point distribution after onboarding diagnostic.",
        "query": trends_query(
            [event_node("onboarding_calibration_completed", "Diagnostic completed", math="total")],
            breakdown="diagnostic_baseline",
        ),
    },
    {
        "name": "Onboarding completion rate",
        "description": "% of users who start and finish onboarding.",
        "query": funnel_query(
            [
                event_node("onboarding_started", "Started"),
                event_node("onboarding_completed", "Completed"),
            ],
            window_days=14,
        ),
    },
    {
        "name": "Full onboarding step funnel",
        "description": "Drop-off at each onboarding Continue tap.",
        "query": onboarding_funnel_query(),
    },
    {
        "name": "D1 quiz activation",
        "description": "Onboarding completers who finish a primary daily quiz within 24h.",
        "query": funnel_query(
            [
                event_node("onboarding_completed", "Onboarding done"),
                event_node(
                    "daily_quiz_completed",
                    "Primary quiz done",
                    properties=[prop_filter("is_supplemental", False)],
                ),
            ],
            window_days=1,
        ),
    },
    {
        "name": "True widget install rate",
        "description": "OS-verified widget install after onboarding.",
        "query": funnel_query(
            [
                event_node("onboarding_completed", "Onboarding done"),
                event_node("widget_installed", "Widget installed"),
            ],
            window_days=7,
        ),
    },
    {
        "name": "Widget intent vs reality",
        "description": "Self-reported widget confirm vs OS-detected install.",
        "query": trends_query(
            [
                event_node("onboarding_widget_confirmed", "Claimed install"),
                event_node("onboarding_widget_deferred", "Deferred"),
                event_node("widget_installed", "OS verified"),
            ]
        ),
    },
    {
        "name": "Trial conversion (all paywalls)",
        "description": "paywall_viewed → checkout_started → subscription_completed.",
        "query": funnel_query(
            [
                event_node("paywall_viewed", "Paywall viewed"),
                event_node("checkout_started", "Checkout started"),
                event_node("subscription_completed", "Subscribed"),
            ],
            window_days=7,
        ),
    },
    {
        "name": "Onboarding paywall funnel",
        "description": "Conversion on onboarding paywall only.",
        "query": funnel_query(
            [
                event_node(
                    "paywall_viewed",
                    "Paywall",
                    properties=[prop_filter("source", "onboarding")],
                ),
                event_node(
                    "checkout_started",
                    "Checkout",
                    properties=[prop_filter("source", "onboarding")],
                ),
                event_node("subscription_completed", "Subscribed"),
            ],
            window_days=1,
        ),
    },
    {
        "name": "Paywall views by source",
        "description": "Which surfaces drive paywall impressions.",
        "query": trends_query(
            [event_node("paywall_viewed", "Paywall views")],
            breakdown="source",
        ),
    },
    {
        "name": "Checkout plan mix",
        "description": "Plans users attempt to purchase.",
        "query": trends_query(
            [event_node("checkout_started", "Checkouts")],
            breakdown="plan_id",
        ),
    },
    {
        "name": "Notification permission grant rate",
        "description": "Prompted → granted.",
        "query": funnel_query(
            [
                event_node("notification_permission_prompted", "Prompted"),
                event_node(
                    "notification_permission_result",
                    "Granted",
                    properties=[prop_filter("granted", True)],
                ),
            ],
            window_days=1,
        ),
    },
    {
        "name": "SAT timeline mix",
        "description": "Onboarding SAT date cohort selection.",
        "query": trends_query(
            [event_node("onboarding_timeline_selected", "Timeline selected")],
            breakdown="sat_test_date",
        ),
    },
    {
        "name": "Daily quiz completion rate",
        "description": "Primary quiz started → completed.",
        "query": funnel_query(
            [
                event_node(
                    "daily_quiz_started",
                    "Started",
                    properties=[prop_filter("is_supplemental", False)],
                ),
                event_node(
                    "daily_quiz_completed",
                    "Completed",
                    properties=[prop_filter("is_supplemental", False)],
                ),
            ],
            window_days=1,
        ),
    },
    {
        "name": "Daily quiz habit (DAU)",
        "description": "Unique users completing primary daily quiz per day.",
        "query": trends_query(
            [
                event_node(
                    "daily_quiz_completed",
                    "Primary quiz completed",
                    properties=[prop_filter("is_supplemental", False)],
                )
            ]
        ),
    },
    {
        "name": "Word mastery velocity",
        "description": "Words marked mastered over time.",
        "query": trends_query(
            [event_node("word_mastered", "Words mastered")],
            breakdown="source",
        ),
    },
    {
        "name": "Friction: daily limit hits",
        "description": "Where free users hit paywalls.",
        "query": trends_query(
            [event_node("daily_limit_hit", "Limit hits")],
            breakdown="source",
        ),
    },
    {
        "name": "Limit hit → subscribe",
        "description": "Friction surface conversion.",
        "query": funnel_query(
            [
                event_node("daily_limit_hit", "Limit hit"),
                event_node("paywall_viewed", "Paywall"),
                event_node("subscription_completed", "Subscribed"),
            ],
            window_days=1,
        ),
    },
    {
        "name": "Tab navigation mix",
        "description": "Today / Library / Insights usage.",
        "query": trends_query(
            [event_node("tab_selected", "Tab selected")],
            breakdown="tab",
        ),
    },
    {
        "name": "Widget tap destinations",
        "description": "Widget deep-link engagement.",
        "query": trends_query(
            [event_node("widget_tapped", "Widget taps")],
            breakdown="destination",
        ),
    },
    {
        "name": "D7 quiz retention",
        "description": "Users returning to complete daily quiz after onboarding.",
        "query": retention_query("onboarding_completed", "daily_quiz_completed"),
    },
    {
        "name": "Event volume sanity check",
        "description": "Confirm all core custom events are firing.",
        "query": trends_query(
            [
                event_node(e, e)
                for e in [
                    "onboarding_started",
                    "onboarding_goals_selected",
                    "onboarding_step_completed",
                    "onboarding_completed",
                    "onboarding_calibration_completed",
                    "notification_tapped",
                    "paywall_viewed",
                    "checkout_started",
                    "subscription_completed",
                    "daily_quiz_started",
                    "daily_quiz_completed",
                    "word_mastered",
                    "daily_limit_hit",
                    "widget_installed",
                ]
            ]
        ),
    },
]


def api_request(method: str, path: str, body: dict | None = None) -> dict:
    url = f"{HOST}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode()
        raise RuntimeError(f"HTTP {exc.code} {method} {path}\n{detail}") from exc


def create_dashboard(name: str, description: str) -> int:
    payload = {
        "name": name,
        "description": description,
        "pinned": True,
    }
    result = api_request("POST", f"/api/projects/{PROJECT_ID}/dashboards/", payload)
    return int(result["id"])


def create_insight(spec: dict, dashboard_id: int) -> int:
    payload = {
        "name": spec["name"],
        "description": spec.get("description", ""),
        "saved": True,
        "favorited": False,
        "query": spec["query"],
        "dashboards": [dashboard_id],
    }
    result = api_request("POST", f"/api/projects/{PROJECT_ID}/insights/", payload)
    return int(result["id"])


def list_dashboards() -> None:
    result = api_request("GET", f"/api/projects/{PROJECT_ID}/dashboards/?limit=50")
    dashboards = result.get("results", result if isinstance(result, list) else [])
    if not dashboards:
        print("No dashboards found.")
        return
    for dashboard in dashboards:
        print(f"{dashboard['id']}\t{dashboard.get('name', '(unnamed)')}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap GlanceSAT PostHog dashboards")
    parser.add_argument("--dry-run", action="store_true", help="Print payloads only")
    parser.add_argument(
        "--list-dashboards",
        action="store_true",
        help="Print dashboard IDs and names, then exit",
    )
    parser.add_argument(
        "--dashboard-id",
        type=int,
        help="Attach insights to an existing dashboard instead of creating a new one",
    )
    parser.add_argument(
        "--from-index",
        type=int,
        default=0,
        help="Start creating insights at this 0-based index (for resume after partial run)",
    )
    parser.add_argument(
        "--count",
        type=int,
        help="Max insights to create from from-index (e.g. --from-index 0 --count 6)",
    )
    args = parser.parse_args()

    if not API_KEY or not PROJECT_ID:
        print(
            "Set POSTHOG_API_KEY (phx_ personal key) and POSTHOG_PROJECT_ID.\n"
            "API key scopes required: dashboard:write, insight:write, project:read\n"
            "Find project ID: PostHog → Project Settings → Project ID",
            file=sys.stderr,
        )
        return 1

    if args.dry_run:
        print(json.dumps({"insights": INSIGHTS}, indent=2))
        return 0

    if args.list_dashboards:
        list_dashboards()
        return 0

    if args.dashboard_id:
        dashboard_id = args.dashboard_id
        print(f"Using dashboard id={dashboard_id}")
    else:
        dashboard_id = create_dashboard(
            "GlanceSAT — Growth & Product",
            "Auto-generated GlanceSAT analytics dashboard (onboarding, revenue, retention, friction).",
        )
        print(f"Created dashboard id={dashboard_id}")

    insights = INSIGHTS[args.from_index :]
    if args.count is not None:
        insights = insights[: args.count]

    for spec in insights:
        insight_id = create_insight(spec, dashboard_id)
        print(f"  ✓ {spec['name']} (insight id={insight_id})")

    print(f"\nDone. Open: {HOST}/project/{PROJECT_ID}/dashboard/{dashboard_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
