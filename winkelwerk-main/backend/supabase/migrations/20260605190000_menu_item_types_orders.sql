create extension if not exists pgcrypto;

alter table if exists public.menu_items
  add column if not exists image_url text;

alter table if exists public.menu_items
  add column if not exists price text;

alter table if exists public.menu_items
  add column if not exists category text;

alter table if exists public.menu_items
  add column if not exists badge text;

alter table if exists public.menu_items
  add column if not exists cta_label text;

alter table if exists public.menu_items
  add column if not exists cta_url text;

alter table if exists public.menu_items
  add column if not exists is_active boolean not null default true;

alter table if exists public.menu_items
  add column if not exists sort_order integer not null default 0;

alter table if exists public.menu_items
  add column if not exists item_type text;

alter table if exists public.menu_items
  add column if not exists menu_period text not null default 'all_day';

alter table if exists public.menu_items
  add column if not exists menu_periods text[] not null default array['all_day']::text[];

alter table if exists public.menu_items
  add column if not exists created_at timestamptz not null default timezone('utc', now());

alter table if exists public.menu_items
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

update public.menu_items
set item_type = case
  when item_type = 'drink' then 'drink'
  else 'food'
end
where item_type is null
   or btrim(item_type) = ''
   or item_type not in ('food', 'drink');

alter table public.menu_items
  alter column item_type set default 'food';

alter table public.menu_items
  alter column item_type set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'menu_items_item_type_check'
  ) then
    alter table public.menu_items
      add constraint menu_items_item_type_check
      check (item_type in ('food', 'drink'));
  end if;
end $$;

create index if not exists menu_items_type_idx
  on public.menu_items (item_type, is_active, sort_order asc);

create table if not exists public.order_requests (
  id bigint generated always as identity primary key,
  customer_name text not null,
  customer_contact text not null,
  pickup_time text,
  notes text,
  items jsonb not null default '[]'::jsonb,
  source_page text,
  total_text text,
  total_value numeric(10,2) not null default 0,
  status text not null default 'new',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists order_requests_created_at_idx
  on public.order_requests (created_at desc);

create index if not exists order_requests_status_idx
  on public.order_requests (status, created_at desc);

insert into public.menu_items (
  title,
  description,
  image_url,
  price,
  category,
  badge,
  cta_label,
  cta_url,
  sort_order,
  is_active,
  item_type,
  menu_period,
  menu_periods
)
select
  v.title,
  v.description,
  v.image_url,
  v.price,
  v.category,
  v.badge,
  v.cta_label,
  v.cta_url,
  v.sort_order,
  v.is_active,
  v.item_type,
  v.menu_period,
  v.menu_periods
from (
  values
    (
      'Hauslimonade',
      'Spritzig, frisch und mit feiner Zitrusnote.',
      'https://images.unsplash.com/photo-1621263764928-df1444c5e859?auto=format&fit=crop&w=1200&q=80',
      '4,90 EUR',
      'Kalt',
      'Hausgemacht',
      null,
      null,
      100,
      true,
      'drink',
      'all_day',
      array['all_day']::text[]
    ),
    (
      'Espresso',
      'Klein, stark und perfekt nach dem Essen.',
      'https://images.unsplash.com/photo-1510591509098-f4fdc6d0ff04?auto=format&fit=crop&w=1200&q=80',
      '2,80 EUR',
      'Heiss',
      'Klassiker',
      null,
      null,
      101,
      true,
      'drink',
      'all_day',
      array['all_day']::text[]
    ),
    (
      'Cappuccino',
      'Cremiger Espresso mit fein aufgeschÃ¤umter Milch.',
      'https://images.unsplash.com/photo-1517701550927-30cf4ba1fe5f?auto=format&fit=crop&w=1200&q=80',
      '3,90 EUR',
      'Heiss',
      'Beliebt',
      null,
      null,
      102,
      true,
      'drink',
      'all_day',
      array['all_day']::text[]
    ),
    (
      'Ingwer-Zitrus-Spritz',
      'Leicht scharf, frisch und schÃ¶n sprudelnd.',
      'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=1200&q=80',
      '5,50 EUR',
      'Mocktail',
      'Neu',
      null,
      null,
      103,
      true,
      'drink',
      'all_day',
      array['all_day']::text[]
    ),
    (
      'Tonic Berry',
      'Beerig, herb und perfekt fÃ¼r warme Abende.',
      'https://images.unsplash.com/photo-1505224522996-4b2f9bf7f6c5?auto=format&fit=crop&w=1200&q=80',
      '6,20 EUR',
      'Signature',
      'Hausbar',
      null,
      null,
      104,
      true,
      'drink',
      'all_day',
      array['all_day']::text[]
    )
) as v(
  title,
  description,
  image_url,
  price,
  category,
  badge,
  cta_label,
  cta_url,
  sort_order,
  is_active,
  item_type,
  menu_period,
  menu_periods
)
where not exists (
  select 1
  from public.menu_items m
  where m.title = v.title
);
