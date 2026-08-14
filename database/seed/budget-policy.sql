-- Generation phase (Phase 6) budget policy. Real, user-provided thresholds (not invented) -
-- see PHASE-6-HANDOFF.md. Run manually: docker compose exec -T postgres psql -U $POSTGRES_USER
-- -d $POSTGRES_DB < database/seed/budget-policy.sql
INSERT INTO budget_policy (
  monthly_budget_usd, daily_budget_usd, warning_threshold, hard_stop_threshold, updated_at
)
SELECT 20.00, 1.00, 0.70, 1.00, now()
WHERE NOT EXISTS (SELECT 1 FROM budget_policy);
