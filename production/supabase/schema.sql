-- Delightful Taste Grill 'N' Kitchen
-- Production foundation for Supabase PostgreSQL.
-- Apply in a NEW Supabase project only after reviewing this schema.
-- Security model: users are linked to branches; owners/admins may access all branches.
create extension if not exists pgcrypto;

create type public.app_role as enum ('owner','admin','manager','cashier','kitchen','inventory');
create type public.order_status as enum ('new','confirmed','preparing','ready','completed','cancelled');
create type public.fulfilment_type as enum ('pickup','delivery');
create type public.payment_method as enum ('cash','bank_transfer','pos','online');
create type public.payment_status as enum ('pending','confirmed','failed','refunded');
create type public.stock_movement_type as enum ('receive','sale_usage','wastage','adjustment','transfer_in','transfer_out','order_reversal');

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  town text,
  state text not null default 'Osun',
  address text,
  phone text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.app_role not null default 'cashier',
  branch_id uuid references public.branches(id) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint profile_branch_role check (
    (role in ('owner','admin') and branch_id is null)
    or (role not in ('owner','admin') and branch_id is not null)
  )
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  phone text not null,
  created_at timestamptz not null default now(),
  unique(phone)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order integer not null default 0,
  is_active boolean not null default true
);

create table public.menu_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.categories(id) on delete set null,
  name text not null,
  description text,
  image_url text,
  base_price numeric(12,2) not null check (base_price >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.branch_menu_availability (
  branch_id uuid not null references public.branches(id) on delete cascade,
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  price_override numeric(12,2) check (price_override is null or price_override >= 0),
  is_available boolean not null default true,
  primary key (branch_id, menu_item_id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number bigint generated always as identity unique,
  branch_id uuid not null references public.branches(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  customer_phone text not null,
  fulfilment public.fulfilment_type not null default 'pickup',
  delivery_address text,
  status public.order_status not null default 'new',
  payment_method public.payment_method not null default 'cash',
  payment_status public.payment_status not null default 'pending',
  subtotal numeric(12,2) not null check (subtotal >= 0),
  delivery_fee numeric(12,2) not null default 0 check (delivery_fee >= 0),
  total numeric(12,2) not null check (total >= 0),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint delivery_address_required check (fulfilment <> 'delivery' or nullif(trim(delivery_address),'') is not null)
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  menu_item_id uuid references public.menu_items(id) on delete set null,
  item_name_snapshot text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(12,2) not null check (unit_price >= 0),
  line_total numeric(12,2) generated always as (quantity * unit_price) stored,
  customizations jsonb not null default '{}'::jsonb
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete restrict,
  branch_id uuid not null references public.branches(id) on delete restrict,
  method public.payment_method not null,
  status public.payment_status not null default 'pending',
  amount numeric(12,2) not null check (amount >= 0),
  reference text unique,
  recorded_by uuid references auth.users(id) on delete set null,
  confirmed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  confirmed_at timestamptz
);

create table public.inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  unit text not null,
  minimum_stock numeric(12,3) not null default 0 check (minimum_stock >= 0),
  is_active boolean not null default true
);

create table public.branch_stock (
  branch_id uuid not null references public.branches(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete cascade,
  quantity numeric(12,3) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (branch_id, inventory_item_id)
);

create table public.recipes (
  menu_item_id uuid not null references public.menu_items(id) on delete cascade,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  quantity_required numeric(12,3) not null check (quantity_required > 0),
  primary key (menu_item_id, inventory_item_id)
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  inventory_item_id uuid not null references public.inventory_items(id) on delete restrict,
  movement_type public.stock_movement_type not null,
  quantity_change numeric(12,3) not null check (quantity_change <> 0),
  note text,
  supplier_name text,
  related_order_id uuid references public.orders(id) on delete set null,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  address text,
  is_active boolean not null default true
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete restrict,
  category text not null,
  description text not null,
  amount numeric(12,2) not null check (amount > 0),
  expense_date date not null default current_date,
  recorded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  branch_id uuid references public.branches(id) on delete set null,
  action text not null,
  table_name text not null,
  record_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index orders_branch_created_idx on public.orders(branch_id, created_at desc);
create index orders_status_branch_idx on public.orders(branch_id, status);
create index order_items_order_idx on public.order_items(order_id);
create index stock_movements_branch_created_idx on public.stock_movements(branch_id, created_at desc);
create index expenses_branch_date_idx on public.expenses(branch_id, expense_date desc);

-- Helper functions use the authenticated profile to enforce branch scope.
create or replace function public.current_app_role()
returns public.app_role
language sql stable security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid() and is_active = true
$$;

create or replace function public.current_branch_id()
returns uuid
language sql stable security definer
set search_path = public
as $$
  select branch_id from public.profiles where id = auth.uid() and is_active = true
$$;

create or replace function public.can_access_branch(target_branch uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
      and (p.role in ('owner','admin') or p.branch_id = target_branch)
  )
$$;

create or replace function public.can_manage_menu()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
      and p.role in ('owner','admin','manager')
  )
$$;

-- RLS is mandatory; no public/anonymous direct access to operational tables.
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.branch_menu_availability enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.inventory_items enable row level security;
alter table public.branch_stock enable row level security;
alter table public.recipes enable row level security;
alter table public.stock_movements enable row level security;
alter table public.suppliers enable row level security;
alter table public.expenses enable row level security;
alter table public.audit_logs enable row level security;

create policy "active users view permitted branches" on public.branches for select to authenticated
using (public.can_access_branch(id));
create policy "owner admin manage branches" on public.branches for all to authenticated
using (public.current_app_role() in ('owner','admin'))
with check (public.current_app_role() in ('owner','admin'));

create policy "users view own profile or owners view all" on public.profiles for select to authenticated
using (id = auth.uid() or public.current_app_role() in ('owner','admin'));
create policy "owners manage profiles" on public.profiles for all to authenticated
using (public.current_app_role() in ('owner','admin'))
with check (public.current_app_role() in ('owner','admin'));

create policy "customers branch scope read" on public.customers for select to authenticated
using (public.current_app_role() in ('owner','admin') or exists (
  select 1 from public.orders o where o.customer_id = customers.id and public.can_access_branch(o.branch_id)
));
create policy "staff create customer" on public.customers for insert to authenticated with check (public.current_app_role() in ('owner','admin','manager','cashier'));
create policy "menu active items readable" on public.categories for select to authenticated using (true);
create policy "menu items readable" on public.menu_items for select to authenticated using (true);
create policy "branch menu readable" on public.branch_menu_availability for select to authenticated using (public.can_access_branch(branch_id));
create policy "menu managers edit categories" on public.categories for all to authenticated using (public.can_manage_menu()) with check (public.can_manage_menu());
create policy "menu managers edit items" on public.menu_items for all to authenticated using (public.can_manage_menu()) with check (public.can_manage_menu());
create policy "menu managers edit branch availability" on public.branch_menu_availability for all to authenticated using (public.can_manage_menu() and public.can_access_branch(branch_id)) with check (public.can_manage_menu() and public.can_access_branch(branch_id));

create policy "orders branch access" on public.orders for select to authenticated using (public.can_access_branch(branch_id));
create policy "staff create orders for own branch" on public.orders for insert to authenticated
with check (public.can_access_branch(branch_id) and (public.current_app_role() in ('owner','admin','manager','cashier')));
create policy "authorized staff update orders" on public.orders for update to authenticated
using (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager','cashier','kitchen'))
with check (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager','cashier','kitchen'));
create policy "order items visible with order branch access" on public.order_items for select to authenticated
using (exists(select 1 from public.orders o where o.id = order_id and public.can_access_branch(o.branch_id)));
create policy "authorized staff add order items" on public.order_items for insert to authenticated
with check (exists(select 1 from public.orders o where o.id = order_id and public.can_access_branch(o.branch_id) and public.current_app_role() in ('owner','admin','manager','cashier')));
create policy "payments branch access" on public.payments for select to authenticated using (public.can_access_branch(branch_id));
create policy "staff record payments" on public.payments for insert to authenticated
with check (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager','cashier'));
create policy "authorized payment status update" on public.payments for update to authenticated
using (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager'))
with check (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager'));

create policy "inventory catalogue readable" on public.inventory_items for select to authenticated using (true);
create policy "branch stock access" on public.branch_stock for select to authenticated using (public.can_access_branch(branch_id));
create policy "inventory roles update stock" on public.branch_stock for all to authenticated
using (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager','inventory'))
with check (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager','inventory'));
create policy "inventory managers edit catalogue" on public.inventory_items for all to authenticated
using (public.current_app_role() in ('owner','admin','manager','inventory'))
with check (public.current_app_role() in ('owner','admin','manager','inventory'));
create policy "recipes readable by staff" on public.recipes for select to authenticated using (true);
create policy "managers edit recipes" on public.recipes for all to authenticated
using (public.can_manage_menu()) with check (public.can_manage_menu());
create policy "stock movements branch access" on public.stock_movements for select to authenticated using (public.can_access_branch(branch_id));
create policy "staff record stock movement" on public.stock_movements for insert to authenticated
with check (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager','inventory'));
create policy "suppliers branch roles read" on public.suppliers for select to authenticated using (public.current_app_role() in ('owner','admin','manager','inventory'));
create policy "managers maintain suppliers" on public.suppliers for all to authenticated
using (public.current_app_role() in ('owner','admin','manager','inventory'))
with check (public.current_app_role() in ('owner','admin','manager','inventory'));
create policy "expenses branch access" on public.expenses for select to authenticated using (public.can_access_branch(branch_id));
create policy "managers record expenses" on public.expenses for insert to authenticated
with check (public.can_access_branch(branch_id) and public.current_app_role() in ('owner','admin','manager'));
create policy "owners review audit logs" on public.audit_logs for select to authenticated using (public.current_app_role() in ('owner','admin'));
create policy "authenticated audit insert" on public.audit_logs for insert to authenticated with check (actor_id = auth.uid());

-- Intentionally do not seed guessed branch names or enable anonymous customer writes.
-- Create the six real branch records after the owner confirms names and addresses.
-- Customer checkout should call a server-side validated Edge Function/API which verifies
-- menu prices, branch availability, totals, payment state, and stock before inserting orders.
