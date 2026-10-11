-- ============================================================================
--  孙家瘦身 · 精神状态测评站 —— Supabase 数据库结构
--  ---------------------------------------------------------------------------
--  用法：登录 Supabase 控制台 → 左侧 SQL Editor → New query →
--        把本文件全部内容粘贴进去 → 点 Run（右下角）
--        看到 "Success. No rows returned" 即完成。
--  可重复执行（幂等），不会重复插入密码。
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. 数据表
-- ---------------------------------------------------------------------------

-- 测评密码
create table if not exists public.access_codes (
  id            bigint generated always as identity primary key,
  code          text        not null unique,   -- 归一化形式：大写、无横线（SJW52H4X）
  display_code  text        not null,          -- 展示形式（SJ-W52H4X）
  max_uses      integer     not null default 3,
  used_count    integer     not null default 0,
  active        boolean     not null default true,
  note          text,                          -- 备注：这个码发给谁了
  batch         text,                          -- 批次
  created_at    timestamptz not null default now(),
  last_used_at  timestamptz
);

-- 每次测评的使用记录（用于看「哪种诊断类型最多」这类统计）
create table if not exists public.code_uses (
  id          bigint generated always as identity primary key,
  code_id     bigint      not null references public.access_codes(id) on delete cascade,
  result_type text,                            -- 诊断类型 key，如 hidden
  avg_score   integer,                         -- 综合评分
  used_at     timestamptz not null default now()
);

create index if not exists access_codes_code_idx  on public.access_codes (code);
create index if not exists code_uses_code_id_idx  on public.code_uses (code_id);
create index if not exists code_uses_used_at_idx  on public.code_uses (used_at);

-- ---------------------------------------------------------------------------
-- 2. 行级安全（RLS）—— 匿名用户读不到任何密码
-- ---------------------------------------------------------------------------
alter table public.access_codes enable row level security;
alter table public.code_uses   enable row level security;

-- 先收回匿名用户的一切直接权限
revoke all on public.access_codes from anon;
revoke all on public.code_uses   from anon;

-- 已登录的管理员可以读/改
drop policy if exists "admin_read_codes"  on public.access_codes;
create policy "admin_read_codes"  on public.access_codes for select to authenticated using (true);

drop policy if exists "admin_write_codes" on public.access_codes;
create policy "admin_write_codes" on public.access_codes for update to authenticated using (true) with check (true);

drop policy if exists "admin_read_uses"   on public.code_uses;
create policy "admin_read_uses"   on public.code_uses   for select to authenticated using (true);

grant select, update on public.access_codes to authenticated;
grant select          on public.code_uses   to authenticated;

-- ---------------------------------------------------------------------------
-- 3. 面向客户端的接口（匿名可调用）
--    这两个函数以 SECURITY DEFINER 运行，绕开 RLS 去查密码表，
--    但只返回「这一次校验的结果」，绝不吐出密码清单。
-- ---------------------------------------------------------------------------

-- 校验密码（不扣次），用于进入门禁
create or replace function public.verify_code(p_code text)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  r public.access_codes;
begin
  if v = '' then
    return json_build_object('ok', false, 'reason', 'empty');
  end if;

  select * into r from public.access_codes where code = v;
  if not found then
    return json_build_object('ok', false, 'reason', 'invalid');
  end if;
  if not r.active then
    return json_build_object('ok', false, 'reason', 'disabled');
  end if;
  if r.used_count >= r.max_uses then
    return json_build_object('ok', false, 'reason', 'exhausted', 'remain', 0, 'max', r.max_uses);
  end if;

  return json_build_object('ok', true, 'remain', r.max_uses - r.used_count, 'max', r.max_uses);
end $$;

-- 扣次（完成一次测评时调用）。用 FOR UPDATE 行锁防止并发重复扣次。
-- 注意：先删掉旧版「p_avg 为 integer」的函数签名，避免 PostgREST 出现重载歧义。
drop function if exists public.consume_code(text, text, integer);
create or replace function public.consume_code(p_code text, p_type text default null, p_avg numeric default null)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  r public.access_codes;
begin
  if v = '' then
    return json_build_object('ok', false, 'reason', 'empty');
  end if;

  select * into r from public.access_codes where code = v for update;
  if not found then
    return json_build_object('ok', false, 'reason', 'invalid');
  end if;
  if not r.active then
    return json_build_object('ok', false, 'reason', 'disabled');
  end if;
  if r.used_count >= r.max_uses then
    return json_build_object('ok', false, 'reason', 'exhausted', 'remain', 0, 'max', r.max_uses);
  end if;

  update public.access_codes
     set used_count = used_count + 1,
         last_used_at = now()
   where id = r.id;

  insert into public.code_uses (code_id, result_type, avg_score)
  values (r.id, nullif(p_type, ''), round(p_avg)::integer);

  return json_build_object('ok', true, 'remain', r.max_uses - r.used_count - 1, 'max', r.max_uses);
end $$;

revoke all on function public.verify_code(text)                        from public;
revoke all on function public.consume_code(text, text, numeric)        from public;
grant execute on function public.verify_code(text)                     to anon, authenticated;
grant execute on function public.consume_code(text, text, numeric)     to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. 管理后台专用接口（必须已登录）
-- ---------------------------------------------------------------------------

-- 批量生成新密码
create or replace function public.admin_generate_codes(
  p_count    integer default 50,
  p_max_uses integer default 3,
  p_batch    text    default null,
  p_note     text    default null
) returns setof public.access_codes
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  chars text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   -- 去掉易混的 0 O 1 I
  v_ids bigint[] := '{}';
  i     integer := 0;
  guard integer := 0;
  c     text;
  nid   bigint;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  p_count    := least(greatest(coalesce(p_count, 50), 1), 500);
  p_max_uses := least(greatest(coalesce(p_max_uses, 3), 1), 100);

  while i < p_count loop
    guard := guard + 1;
    if guard > p_count * 60 then exit; end if;

    c := 'SJ';
    for k in 1..6 loop
      c := c || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    end loop;

    begin
      insert into public.access_codes (code, display_code, max_uses, batch, note)
      values (c, 'SJ-' || substr(c, 3), p_max_uses, p_batch, p_note)
      returning id into nid;
      v_ids := v_ids || nid;
      i := i + 1;
    exception when unique_violation then
      null;   -- 撞码，重试
    end;
  end loop;

  return query select * from public.access_codes where id = any(v_ids) order by id;
end $$;

-- 把某个密码的次数重置为 0（重新启用一个用完的码）
create or replace function public.admin_reset_uses(p_code text)
returns json
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  n integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  update public.access_codes
     set used_count = 0, last_used_at = null
   where code = v;
  get diagnostics n = row_count;

  if n = 0 then
    return json_build_object('ok', false, 'reason', 'invalid');
  end if;
  return json_build_object('ok', true);
end $$;

revoke all on function public.admin_generate_codes(integer, integer, text, text) from public;
revoke all on function public.admin_reset_uses(text)                             from public;
revoke all on function public.admin_generate_codes(integer, integer, text, text) from anon;
revoke all on function public.admin_reset_uses(text)                             from anon;
grant execute on function public.admin_generate_codes(integer, integer, text, text) to authenticated;
grant execute on function public.admin_reset_uses(text)                             to authenticated;

-- ---------------------------------------------------------------------------
-- 5. 首批 50 个密码
-- ---------------------------------------------------------------------------
insert into public.access_codes (code, display_code, max_uses, batch, note) values
  ('SJW52H4X', 'SJ-W52H4X', 3, '首批', ''),
  ('SJY6J6EZ', 'SJ-Y6J6EZ', 3, '首批', ''),
  ('SJHQMBF4', 'SJ-HQMBF4', 3, '首批', ''),
  ('SJF8YJS7', 'SJ-F8YJS7', 3, '首批', ''),
  ('SJMH92UJ', 'SJ-MH92UJ', 3, '首批', ''),
  ('SJZHJPJY', 'SJ-ZHJPJY', 3, '首批', ''),
  ('SJQJ8HED', 'SJ-QJ8HED', 3, '首批', ''),
  ('SJMWT77B', 'SJ-MWT77B', 3, '首批', ''),
  ('SJ3WQVD5', 'SJ-3WQVD5', 3, '首批', ''),
  ('SJPDHHSE', 'SJ-PDHHSE', 3, '首批', ''),
  ('SJ3KEK9K', 'SJ-3KEK9K', 3, '首批', ''),
  ('SJ5F7SNR', 'SJ-5F7SNR', 3, '首批', ''),
  ('SJW3RLEH', 'SJ-W3RLEH', 3, '首批', ''),
  ('SJSXSUXX', 'SJ-SXSUXX', 3, '首批', ''),
  ('SJTN4HEM', 'SJ-TN4HEM', 3, '首批', ''),
  ('SJZSDCKT', 'SJ-ZSDCKT', 3, '首批', ''),
  ('SJSPNP6R', 'SJ-SPNP6R', 3, '首批', ''),
  ('SJZSA5FF', 'SJ-ZSA5FF', 3, '首批', ''),
  ('SJGNHYCA', 'SJ-GNHYCA', 3, '首批', ''),
  ('SJF97MSY', 'SJ-F97MSY', 3, '首批', ''),
  ('SJCNEZXU', 'SJ-CNEZXU', 3, '首批', ''),
  ('SJ724AKF', 'SJ-724AKF', 3, '首批', ''),
  ('SJLXVPTJ', 'SJ-LXVPTJ', 3, '首批', ''),
  ('SJFLC6CC', 'SJ-FLC6CC', 3, '首批', ''),
  ('SJ8YKZRK', 'SJ-8YKZRK', 3, '首批', ''),
  ('SJ8VEJ9X', 'SJ-8VEJ9X', 3, '首批', ''),
  ('SJ9WK6KH', 'SJ-9WK6KH', 3, '首批', ''),
  ('SJZZ3XLF', 'SJ-ZZ3XLF', 3, '首批', ''),
  ('SJ4KMBHG', 'SJ-4KMBHG', 3, '首批', ''),
  ('SJFEM58J', 'SJ-FEM58J', 3, '首批', ''),
  ('SJXEKC6C', 'SJ-XEKC6C', 3, '首批', ''),
  ('SJW5BTCP', 'SJ-W5BTCP', 3, '首批', ''),
  ('SJ7NK2BY', 'SJ-7NK2BY', 3, '首批', ''),
  ('SJ3JHA6T', 'SJ-3JHA6T', 3, '首批', ''),
  ('SJD2Q8EU', 'SJ-D2Q8EU', 3, '首批', ''),
  ('SJNVP697', 'SJ-NVP697', 3, '首批', ''),
  ('SJCDR7PS', 'SJ-CDR7PS', 3, '首批', ''),
  ('SJ4UJ9KA', 'SJ-4UJ9KA', 3, '首批', ''),
  ('SJCBR54R', 'SJ-CBR54R', 3, '首批', ''),
  ('SJJHVK66', 'SJ-JHVK66', 3, '首批', ''),
  ('SJTT5PMU', 'SJ-TT5PMU', 3, '首批', ''),
  ('SJKB8PB5', 'SJ-KB8PB5', 3, '首批', ''),
  ('SJS4BC5B', 'SJ-S4BC5B', 3, '首批', ''),
  ('SJYK3YQW', 'SJ-YK3YQW', 3, '首批', ''),
  ('SJW9KPPB', 'SJ-W9KPPB', 3, '首批', ''),
  ('SJ87KKTW', 'SJ-87KKTW', 3, '首批', ''),
  ('SJ5RHDGP', 'SJ-5RHDGP', 3, '首批', ''),
  ('SJYDKYVZ', 'SJ-YDKYVZ', 3, '首批', ''),
  ('SJASK7FU', 'SJ-ASK7FU', 3, '首批', ''),
  ('SJDMCHTC', 'SJ-DMCHTC', 3, '首批', '')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- 6. 自检（执行完应看到 50 行密码）
-- ---------------------------------------------------------------------------
select count(*) as 密码总数,
       sum(case when used_count >= max_uses then 1 else 0 end) as 已用完,
       sum(used_count) as 累计测评次数
  from public.access_codes;
