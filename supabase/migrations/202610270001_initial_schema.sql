-- Supabase schema for OilPro. Business rows always belong to one workshop.
-- The client's Drift database remains the offline source of truth.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.workshops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table public.workshop_members (
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null check (role in ('owner', 'manager', 'staff')),
  created_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create index workshop_members_user_id_idx
  on public.workshop_members(user_id);

create function private.is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workshop_members as member
    where member.workspace_id = p_workspace_id
      and member.user_id = (select auth.uid())
  );
$$;

create function private.has_workspace_role(
  p_workspace_id uuid,
  p_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.workshop_members as member
    where member.workspace_id = p_workspace_id
      and member.user_id = (select auth.uid())
      and member.role = any (p_roles)
  );
$$;

revoke all on function private.is_workspace_member(uuid)
  from public, anon, authenticated;
revoke all on function private.has_workspace_role(uuid, text[])
  from public, anon, authenticated;
grant execute on function private.is_workspace_member(uuid) to authenticated;
grant execute on function private.has_workspace_role(uuid, text[]) to authenticated;

-- A new workshop creator becomes its first owner atomically.
create function private.add_workshop_owner()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.workshop_members (workspace_id, user_id, role)
  values (new.id, new.created_by, 'owner');
  return new;
end;
$$;

revoke all on function private.add_workshop_owner() from public, anon, authenticated;

create trigger workshops_add_owner_after_insert
after insert on public.workshops
for each row execute function private.add_workshop_owner();

create function private.prevent_workshop_identity_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.created_by is distinct from old.created_by
     or new.created_at is distinct from old.created_at then
    raise exception 'Workshop identity and creation time are immutable';
  end if;
  return new;
end;
$$;

revoke all on function private.prevent_workshop_identity_change()
  from public, anon, authenticated;

create trigger workshops_prevent_identity_change
before update on public.workshops
for each row execute function private.prevent_workshop_identity_change();

create table public.clients (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  name text not null,
  phone text,
  note text,
  unique (workspace_id, id)
);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_id uuid not null,
  plate text not null,
  vin text,
  brand text not null,
  model text not null,
  year integer,
  mileage integer not null default 0 check (mileage >= 0),
  unique (workspace_id, id),
  unique (workspace_id, id, client_id),
  foreign key (workspace_id, client_id)
    references public.clients(workspace_id, id) on delete restrict
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  name text not null,
  kind text not null check (kind in ('oil', 'filter', 'fluid', 'gearOil', 'other')),
  unit text not null default 'шт',
  price_kopecks bigint not null default 0 check (price_kopecks >= 0),
  cost_kopecks bigint not null default 0 check (cost_kopecks >= 0),
  -- Server-managed projection. Stock changes only through stock_movements.
  stock_milli bigint not null default 0 check (stock_milli >= 0),
  min_stock_milli bigint not null default 0 check (min_stock_milli >= 0),
  gearbox text check (gearbox is null or gearbox in ('auto', 'manual', 'robot')),
  unique (workspace_id, id)
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  client_id uuid not null,
  vehicle_id uuid not null,
  mileage integer not null check (mileage >= 0),
  status text not null default 'draft' check (status in ('draft', 'completed')),
  completed_at timestamptz,
  total_kopecks bigint not null default 0 check (total_kopecks >= 0),
  note text,
  unique (workspace_id, id),
  foreign key (workspace_id, client_id)
    references public.clients(workspace_id, id) on delete restrict,
  foreign key (workspace_id, vehicle_id, client_id)
    references public.vehicles(workspace_id, id, client_id) on delete restrict,
  check (
    (status = 'draft' and completed_at is null)
    or (status = 'completed' and completed_at is not null)
  )
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  order_id uuid not null,
  product_id uuid,
  kind text not null check (kind in ('product', 'work')),
  title text not null,
  qty_milli bigint not null default 1000 check (qty_milli > 0),
  price_kopecks bigint not null check (price_kopecks >= 0),
  cost_kopecks bigint not null default 0 check (cost_kopecks >= 0),
  unique (workspace_id, id),
  foreign key (workspace_id, order_id)
    references public.orders(workspace_id, id) on delete restrict,
  foreign key (workspace_id, product_id)
    references public.products(workspace_id, id) on delete restrict,
  check (
    (kind = 'work' and product_id is null)
    or (kind = 'product' and product_id is not null)
  )
);

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  product_id uuid not null,
  kind text not null check (kind in ('receipt', 'sale', 'adjustment')),
  delta_milli bigint not null,
  cost_kopecks bigint check (cost_kopecks is null or cost_kopecks >= 0),
  note text,
  order_id uuid,
  unique (workspace_id, id),
  foreign key (workspace_id, product_id)
    references public.products(workspace_id, id) on delete restrict,
  foreign key (workspace_id, order_id)
    references public.orders(workspace_id, id) on delete restrict,
  check (
    (kind = 'receipt' and delta_milli > 0)
    or (kind = 'sale' and delta_milli < 0)
    or (kind = 'adjustment' and delta_milli <> 0)
  ),
  check (deleted_at is null)
);

create function private.apply_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.products
  set stock_milli = stock_milli + new.delta_milli,
      updated_at = greatest(updated_at, now())
  where workspace_id = new.workspace_id
    and id = new.product_id
    and stock_milli + new.delta_milli >= 0;

  if not found then
    raise exception using
      errcode = '23514',
      message = 'Insufficient stock for this movement';
  end if;

  return new;
end;
$$;

revoke all on function private.apply_stock_movement() from public, anon, authenticated;

create trigger stock_movements_apply_stock_after_insert
after insert on public.stock_movements
for each row execute function private.apply_stock_movement();

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  product_id uuid not null,
  title text not null,
  qty_milli bigint not null check (qty_milli > 0),
  price_kopecks bigint not null check (price_kopecks >= 0),
  cost_kopecks bigint not null default 0 check (cost_kopecks >= 0),
  note text,
  unique (workspace_id, id),
  foreign key (workspace_id, product_id)
    references public.products(workspace_id, id) on delete restrict
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workshops(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  title text not null,
  amount_kopecks bigint not null check (amount_kopecks >= 0),
  unique (workspace_id, id)
);

-- Indexes used by list screens, joins, and workspace policies.
create index clients_workspace_name_idx on public.clients(workspace_id, name);
create index vehicles_workspace_plate_idx on public.vehicles(workspace_id, plate);
create index vehicles_workspace_client_idx on public.vehicles(workspace_id, client_id);
create index products_workspace_name_idx on public.products(workspace_id, name);
create index orders_workspace_completed_idx
  on public.orders(workspace_id, completed_at desc);
create index orders_workspace_vehicle_completed_idx
  on public.orders(workspace_id, vehicle_id, completed_at desc);
create index order_items_workspace_order_idx
  on public.order_items(workspace_id, order_id, created_at);
create index order_items_workspace_product_idx
  on public.order_items(workspace_id, product_id);
create index stock_movements_workspace_product_idx
  on public.stock_movements(workspace_id, product_id, created_at desc);
create index stock_movements_workspace_order_idx
  on public.stock_movements(workspace_id, order_id);
create index sales_workspace_created_idx on public.sales(workspace_id, created_at desc);
create index expenses_workspace_created_idx
  on public.expenses(workspace_id, created_at desc);

create function private.prevent_identity_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.workspace_id is distinct from old.workspace_id
     or new.created_at is distinct from old.created_at then
    raise exception 'Record identity and creation time are immutable';
  end if;
  return new;
end;
$$;

revoke all on function private.prevent_identity_change() from public, anon, authenticated;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'clients', 'vehicles', 'products', 'orders', 'order_items',
    'stock_movements', 'sales', 'expenses'
  ] loop
    execute format(
      'create trigger %I before update on public.%I '
      'for each row execute function private.prevent_identity_change()',
      table_name || '_prevent_identity_change', table_name
    );
  end loop;
end;
$$;

-- Enable RLS and explicitly grant only the operations used by the app.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'clients', 'vehicles', 'products', 'orders', 'order_items',
    'stock_movements', 'sales', 'expenses'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on table public.%I from anon, authenticated', table_name);
    if table_name = 'stock_movements' then
      execute format('grant select, insert on table public.%I to authenticated', table_name);
    elsif table_name = 'products' then
      execute 'grant select on table public.products to authenticated';
      execute 'grant insert (id, workspace_id, created_at, updated_at, deleted_at, '
        'name, kind, unit, price_kopecks, cost_kopecks, min_stock_milli, gearbox) '
        'on table public.products to authenticated';
      execute 'grant update (updated_at, deleted_at, name, kind, unit, price_kopecks, '
        'cost_kopecks, min_stock_milli, gearbox) '
        'on table public.products to authenticated';
    else
      execute format('grant select, insert, update on table public.%I to authenticated', table_name);
    end if;

    execute format(
      'create policy %I on public.%I for select to authenticated '
      'using ((select private.is_workspace_member(workspace_id)))',
      table_name || '_member_select', table_name
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated '
      'with check ((select private.is_workspace_member(workspace_id)))',
      table_name || '_member_insert', table_name
    );
    if table_name <> 'stock_movements' then
      execute format(
        'create policy %I on public.%I for update to authenticated '
        'using ((select private.is_workspace_member(workspace_id))) '
        'with check ((select private.is_workspace_member(workspace_id)))',
        table_name || '_member_update', table_name
      );
    end if;
  end loop;
end;
$$;

alter table public.workshops enable row level security;
revoke all on table public.workshops from anon, authenticated;
grant select, insert, update on table public.workshops to authenticated;

create policy workshops_member_select
  on public.workshops for select to authenticated
  using ((select private.is_workspace_member(id)));
create policy workshops_creator_insert
  on public.workshops for insert to authenticated
  with check (created_by = (select auth.uid()));
create policy workshops_owner_update
  on public.workshops for update to authenticated
  using ((select private.has_workspace_role(id, array['owner', 'manager'])))
  with check ((select private.has_workspace_role(id, array['owner', 'manager'])));

alter table public.workshop_members enable row level security;
revoke all on table public.workshop_members from anon, authenticated;
grant select on table public.workshop_members to authenticated;

create policy workshop_members_member_select
  on public.workshop_members for select to authenticated
  using ((select private.is_workspace_member(workspace_id)));
