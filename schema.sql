-- ============================================================
-- My Catering — Supabase schema, RLS, and RPCs
-- Run this ONCE in the Supabase SQL Editor (project:
-- https://jqqnnkzozjskziaizajg.supabase.co), then add
-- "my_catering" to Project Settings -> API -> Exposed Schemas.
-- ============================================================

create schema if not exists my_catering;

create or replace function my_catering.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- ============================================================
-- ACCOUNTS (tenant)
-- ============================================================
create table my_catering.accounts (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null unique references auth.users(id),
  business_name text not null,
  signature text,
  contact_email text,
  contact_phone text,
  status text not null default 'trial' check (status in ('trial','approved','blocked')),
  trial_started_at timestamptz,
  trial_extended_days int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_accounts_updated before update on my_catering.accounts
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- STAFF (team members — owner is a staff row too, role='owner')
-- ============================================================
create table my_catering.staff (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  user_id uuid unique references auth.users(id),
  full_name text not null,
  phone text,
  role text not null default 'staff' check (role in ('owner','staff')),
  status text not null default 'invited' check (status in ('invited','active','disabled')),
  invite_email text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index uq_staff_invite_email on my_catering.staff(account_id, lower(invite_email))
  where invite_email is not null;
create index ix_staff_account on my_catering.staff(account_id);
create trigger trg_staff_updated before update on my_catering.staff
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- CLIENTS
-- ============================================================
create table my_catering.clients (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  name text not null,
  contact_person text,
  phone text,
  email text,
  notes text,
  status text not null default 'active' check (status in ('active','served','not_converted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_clients_account on my_catering.clients(account_id);
create trigger trg_clients_updated before update on my_catering.clients
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- EVENTS / FUNCTIONS (stage = pipeline progress 1-6, independent of event_status)
-- ============================================================
create table my_catering.events (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  client_id uuid not null references my_catering.clients(id) on delete cascade,
  function_type text not null check (function_type in
    ('Haldi','Mehendi','Sangeet','Wedding','Reception','Engagement','Gruh Shanti',
     'House Warming','Inauguration','Corporate Dinner','Birthday','Anniversary',
     'Small Party','Other')),
  event_date date not null,
  pax int,
  venue text,
  time_of_day text check (time_of_day in ('Morning','Afternoon','Evening','Night')),
  meal_type text check (meal_type in
    ('Breakfast','Lunch','High Tea','Snacks','Dinner','Refreshment','Full Day')),
  notes text,
  stage smallint not null default 1 check (stage between 1 and 6),
  event_status text not null default 'active' check (event_status in ('active','served','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_events_account on my_catering.events(account_id);
create index ix_events_client on my_catering.events(client_id);
create index ix_events_date on my_catering.events(event_date);
create trigger trg_events_updated before update on my_catering.events
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- EVENT ITEMS
-- ============================================================
create table my_catering.event_items (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  event_id uuid not null references my_catering.events(id) on delete cascade,
  item_name text not null,
  category text,
  qty numeric(10,2),
  unit text check (unit in ('pax','pcs','kg','ltr','portion','plate','box','dozen')),
  created_at timestamptz not null default now()
);
create index ix_event_items_event on my_catering.event_items(event_id);

-- ============================================================
-- VENDORS
-- ============================================================
create table my_catering.vendors (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  agency_name text not null,
  cuisine text,
  contact_person text,
  contact_person_2 text,
  contact_person_3 text,
  contact_number text,
  contact_number_2 text,
  contact_number_3 text,
  base_city text,
  whatsapp_group_link text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_vendors_account on my_catering.vendors(account_id);
create trigger trg_vendors_updated before update on my_catering.vendors
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- ITEM_VENDORS — master catalog: item -> default vendor(s)
-- ============================================================
create table my_catering.item_vendors (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  item_name text not null,
  category text,
  vendor_id uuid references my_catering.vendors(id) on delete set null,
  vendor_item_name text,
  created_at timestamptz not null default now()
);
create index ix_item_vendors_account on my_catering.item_vendors(account_id);
create index ix_item_vendors_item on my_catering.item_vendors(account_id, item_name);

-- ============================================================
-- EVENT_VENDORS — vendor assigned to a specific item within an event (staff-visible)
-- ============================================================
create table my_catering.event_vendors (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  event_id uuid not null references my_catering.events(id) on delete cascade,
  event_item_id uuid not null references my_catering.event_items(id) on delete cascade,
  vendor_id uuid references my_catering.vendors(id) on delete set null,
  agency_name text,
  item_name text,
  vendor_item_name text,
  status text not null default 'pending' check (status in ('pending','quote_pending','confirmed')),
  quoted_cost numeric(12,2),
  confirmed_cost numeric(12,2),
  paid_to_vendor numeric(12,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_event_vendors_event on my_catering.event_vendors(event_id);
create trigger trg_event_vendors_updated before update on my_catering.event_vendors
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- EVENT_PRICING + EVENT_PAYMENTS — owner-only cost/margin ledger
-- ============================================================
create table my_catering.event_pricing (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  event_id uuid not null unique references my_catering.events(id) on delete cascade,
  other_costs numeric(12,2) not null default 0,
  client_price_quote numeric(12,2),
  advance_required numeric(12,2),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_event_pricing_updated before update on my_catering.event_pricing
  for each row execute function my_catering.set_updated_at();

create table my_catering.event_payments (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  event_id uuid not null references my_catering.events(id) on delete cascade,
  amount numeric(12,2) not null,
  payment_date date not null default current_date,
  mode text check (mode in ('cash','upi','bank_transfer','cheque','other')),
  notes text,
  created_at timestamptz not null default now()
);
create index ix_event_payments_event on my_catering.event_payments(event_id);

create or replace view my_catering.event_financials
with (security_invoker = true) as
select
  e.id as event_id,
  e.account_id,
  coalesce(sum(coalesce(ev.confirmed_cost, ev.quoted_cost)), 0) as vendor_cost_total,
  coalesce(ep.other_costs, 0) as other_costs,
  coalesce(sum(coalesce(ev.confirmed_cost, ev.quoted_cost)), 0) + coalesce(ep.other_costs, 0) as total_cost,
  ep.client_price_quote,
  coalesce(ep.client_price_quote, 0)
    - (coalesce(sum(coalesce(ev.confirmed_cost, ev.quoted_cost)), 0) + coalesce(ep.other_costs, 0)) as margin,
  (select coalesce(sum(amount),0) from my_catering.event_payments p where p.event_id = e.id) as amount_received
from my_catering.events e
left join my_catering.event_vendors ev on ev.event_id = e.id
left join my_catering.event_pricing ep on ep.event_id = e.id
group by e.id, e.account_id, ep.other_costs, ep.client_price_quote;

-- ============================================================
-- TASKS (auto-generated + standalone reminders)
-- ============================================================
create table my_catering.tasks (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  event_id uuid references my_catering.events(id) on delete cascade,
  task text not null,
  due_date date,
  tag text,
  status text not null default 'pending' check (status in ('pending','done')),
  type text not null default 'reminder' check (type in ('reminder','auto')),
  assigned_to uuid references my_catering.staff(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_tasks_account on my_catering.tasks(account_id);
create index ix_tasks_event on my_catering.tasks(event_id);
create index ix_tasks_due on my_catering.tasks(due_date);
create trigger trg_tasks_updated before update on my_catering.tasks
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- TASTINGS (real client_id FK, optional event_id link)
-- ============================================================
create table my_catering.tastings (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  client_id uuid not null references my_catering.clients(id) on delete cascade,
  event_id uuid references my_catering.events(id) on delete set null,
  tasting_date date not null,
  time time,
  venue_type text check (venue_type in ('clients_place','our_kitchen','other')),
  venue text,
  status text not null default 'scheduled' check (status in ('scheduled','done','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index ix_tastings_account on my_catering.tastings(account_id);
create index ix_tastings_client on my_catering.tastings(client_id);
create trigger trg_tastings_updated before update on my_catering.tastings
  for each row execute function my_catering.set_updated_at();

-- ============================================================
-- MENUS_SENT — real Supabase Storage file reference
-- ============================================================
create table my_catering.menus_sent (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  event_id uuid not null references my_catering.events(id) on delete cascade,
  meal_function text,
  version text check (version in ('V1','V2','V3','Final')),
  file_path text not null,
  file_name text,
  uploaded_by uuid references my_catering.staff(id),
  created_at timestamptz not null default now()
);
create index ix_menus_sent_event on my_catering.menus_sent(event_id);

-- ============================================================
-- TASTING_PHOTOS
-- ============================================================
create table my_catering.tasting_photos (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references my_catering.accounts(id) on delete cascade,
  tasting_id uuid not null references my_catering.tastings(id) on delete cascade,
  file_path text not null,
  file_name text,
  uploaded_by uuid references my_catering.staff(id),
  created_at timestamptz not null default now()
);
create index ix_tasting_photos_tasting on my_catering.tasting_photos(tasting_id);

-- ============================================================
-- RLS — core helpers
-- ============================================================
create or replace function my_catering.current_account_id()
returns uuid language sql stable security definer set search_path = my_catering, public as $$
  select account_id from my_catering.staff
  where user_id = auth.uid() and status = 'active' limit 1
$$;
grant execute on function my_catering.current_account_id() to authenticated;

create or replace function my_catering.is_owner()
returns boolean language sql stable security definer set search_path = my_catering, public as $$
  select exists(select 1 from my_catering.staff where user_id = auth.uid() and role='owner' and status='active')
$$;
grant execute on function my_catering.is_owner() to authenticated;

-- ============================================================
-- RLS — standard tenant-scoped pattern (staff-visible tables)
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array[
    'clients','events','event_items','vendors','item_vendors',
    'event_vendors','tasks','tastings','menus_sent','tasting_photos'
  ]
  loop
    execute format('alter table my_catering.%I enable row level security;', t);
    execute format('create policy tenant_select on my_catering.%I for select using (account_id = my_catering.current_account_id());', t);
    execute format('create policy tenant_insert on my_catering.%I for insert with check (account_id = my_catering.current_account_id());', t);
    execute format('create policy tenant_update on my_catering.%I for update using (account_id = my_catering.current_account_id()) with check (account_id = my_catering.current_account_id());', t);
    execute format('create policy tenant_delete on my_catering.%I for delete using (account_id = my_catering.current_account_id());', t);
  end loop;
end $$;

-- ============================================================
-- RLS — owner-only pattern (cost/margin/payments)
-- ============================================================
alter table my_catering.event_pricing enable row level security;
create policy owner_all on my_catering.event_pricing
  for all using (account_id = my_catering.current_account_id() and my_catering.is_owner())
  with check (account_id = my_catering.current_account_id() and my_catering.is_owner());

alter table my_catering.event_payments enable row level security;
create policy owner_all on my_catering.event_payments
  for all using (account_id = my_catering.current_account_id() and my_catering.is_owner())
  with check (account_id = my_catering.current_account_id() and my_catering.is_owner());

-- ============================================================
-- RLS — accounts / staff (special-cased)
-- ============================================================
alter table my_catering.accounts enable row level security;
create policy accounts_select on my_catering.accounts for select using (id = my_catering.current_account_id());
create policy accounts_update on my_catering.accounts for update using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
revoke update on my_catering.accounts from authenticated;
grant update (business_name, signature, contact_email, contact_phone) on my_catering.accounts to authenticated;
-- No insert/delete policy — accounts only created via bootstrap_account() RPC below.

alter table my_catering.staff enable row level security;
create policy staff_select on my_catering.staff for select using (account_id = my_catering.current_account_id());
-- No insert/update policy — staff rows only created/linked via the RPCs below.

-- ============================================================
-- Bootstrap / invite / trial RPCs
-- ============================================================
create or replace function my_catering.bootstrap_account(p_business_name text, p_contact_phone text)
returns my_catering.accounts language plpgsql security definer set search_path = my_catering, public as $$
declare v_account my_catering.accounts;
begin
  if exists (select 1 from my_catering.staff where user_id = auth.uid()) then
    raise exception 'Account already exists for this user';
  end if;
  insert into my_catering.accounts (owner_user_id, business_name, signature, contact_email, contact_phone)
  values (auth.uid(), p_business_name, p_business_name, auth.email(), p_contact_phone)
  returning * into v_account;
  insert into my_catering.staff (account_id, user_id, full_name, phone, role, status)
  values (v_account.id, auth.uid(), p_business_name, p_contact_phone, 'owner', 'active');
  return v_account;
end $$;
grant execute on function my_catering.bootstrap_account(text,text) to authenticated;

create or replace function my_catering.invite_staff(p_email text, p_full_name text, p_phone text)
returns my_catering.staff language plpgsql security definer set search_path = my_catering, public as $$
declare v_account_id uuid; v_row my_catering.staff;
begin
  select account_id into v_account_id from my_catering.staff
    where user_id = auth.uid() and role = 'owner' and status = 'active';
  if v_account_id is null then raise exception 'Only the account owner can invite team members'; end if;
  insert into my_catering.staff (account_id, invite_email, full_name, phone, role, status)
  values (v_account_id, lower(p_email), p_full_name, p_phone, 'staff', 'invited')
  returning * into v_row;
  return v_row;
end $$;
grant execute on function my_catering.invite_staff(text,text,text) to authenticated;

create or replace function my_catering.claim_staff_invite()
returns my_catering.staff language plpgsql security definer set search_path = my_catering, public as $$
declare v_row my_catering.staff;
begin
  update my_catering.staff set user_id = auth.uid(), status = 'active'
  where invite_email = lower(auth.email()) and status = 'invited' and user_id is null
  returning * into v_row;
  if v_row.id is null then raise exception 'No pending invite found for this email'; end if;
  return v_row;
end $$;
grant execute on function my_catering.claim_staff_invite() to authenticated;

create or replace function my_catering.start_trial_if_needed()
returns void language plpgsql security definer set search_path = my_catering, public as $$
begin
  update my_catering.accounts set trial_started_at = now()
  where id = my_catering.current_account_id() and trial_started_at is null;
end $$;
grant execute on function my_catering.start_trial_if_needed() to authenticated;

-- ============================================================
-- File storage
-- ============================================================
insert into storage.buckets (id, name, public)
values ('attachments', 'attachments', false)
on conflict (id) do nothing;

create policy "my_catering tenant read own files" on storage.objects for select using (
  bucket_id = 'attachments' and (storage.foldername(name))[1] = my_catering.current_account_id()::text);
create policy "my_catering tenant upload own files" on storage.objects for insert with check (
  bucket_id = 'attachments' and (storage.foldername(name))[1] = my_catering.current_account_id()::text);
create policy "my_catering tenant delete own files" on storage.objects for delete using (
  bucket_id = 'attachments' and (storage.foldername(name))[1] = my_catering.current_account_id()::text);

-- ============================================================
-- Done. Next: Supabase Dashboard -> Project Settings -> API ->
-- Exposed Schemas -> add "my_catering"
-- ============================================================
