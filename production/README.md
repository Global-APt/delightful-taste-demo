# Delightful Taste Grill 'N' Kitchen — production foundation

This folder begins the production build separately from the public prototype.

## Files
- `supabase/schema.sql`: initial PostgreSQL schema, branch-scoped role model, and Row Level Security policies.

## Important
- Do not put a Supabase service-role key in browser code or commit secrets.
- Do not use the public prototype for real customer orders, stock or payment records.
- The schema intentionally does not invent the six real branch names.
- Public customer checkout must be implemented through a server-side validated API/Edge Function. Never allow anonymous clients to set prices, totals, payment status or inventory changes.
- Before real deployment, review and test every RLS policy, order/stock transaction, backup, privacy requirement and payment workflow.
