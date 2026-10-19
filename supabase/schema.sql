-- ============================================================
-- 垂钓 App · Supabase 数据库脚本
-- 在 Supabase 控制台 → SQL Editor 中全选执行
-- ============================================================

-- 1) 用户资料表（与 auth.users 关联）
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  avatar_url text,
  created_at timestamptz default now()
);

-- 2) 动态/渔获表
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  body text,
  image_urls text[] default '{}',
  location_name text,
  lat double precision,
  lng double precision,
  like_count int default 0,
  comment_count int default 0,
  created_at timestamptz default now()
);

-- 3) 点赞表（唯一约束防止重复点赞）
create table if not exists public.likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  unique (post_id, user_id)
);

-- 4) 评论表
create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  content text not null,
  created_at timestamptz default now()
);

-- 索引
create index if not exists posts_created_idx on public.posts (created_at desc);
create index if not exists likes_post_idx on public.likes (post_id);
create index if not exists comments_post_idx on public.comments (post_id);

-- ============================================================
-- 行级安全（RLS）：读公开，写需登录
-- ============================================================
alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;

-- profiles：任何人可读，本人可写
create policy "profiles_read" on public.profiles for select using (true);
create policy "profiles_upsert" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update" on public.profiles for update using (auth.uid() = id);

-- posts：公开读，作者可写
create policy "posts_read" on public.posts for select using (true);
create policy "posts_insert" on public.posts for insert with check (auth.uid() = user_id);
create policy "posts_delete" on public.posts for delete using (auth.uid() = user_id);

-- likes / comments：公开读，登录可写，本人可删
create policy "likes_read" on public.likes for select using (true);
create policy "likes_write" on public.likes for insert with check (auth.uid() = user_id);
create policy "likes_del" on public.likes for delete using (auth.uid() = user_id);
create policy "comments_read" on public.comments for select using (true);
create policy "comments_write" on public.comments for insert with check (auth.uid() = user_id);
create policy "comments_del" on public.comments for delete using (auth.uid() = user_id);

-- ============================================================
-- 计数维护函数（点赞/评论后更新 posts 上的计数）
-- ============================================================
create or replace function public.increment_like(pid uuid)
returns void language sql as $$
  update public.posts set like_count = like_count + 1 where id = pid;
$$;

create or replace function public.decrement_like(pid uuid)
returns void language sql as $$
  update public.posts set like_count = greatest(like_count - 1, 0) where id = pid;
$$;

create or replace function public.increment_comment(pid uuid)
returns void language sql as $$
  update public.posts set comment_count = comment_count + 1 where id = pid;
$$;

-- ============================================================
-- 图片存储桶（也可在 Storage 页面手动创建，设为 Public）
-- ============================================================
insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do nothing;

create policy "images_public_read" on storage.objects
  for select using (bucket_id = 'post-images');
create policy "images_auth_write" on storage.objects
  for insert with check (bucket_id = 'post-images' and auth.uid() is not null);

-- ============================================================
-- V2 新增：钓点 spots 表 + 钓点报错 spot_reports 表
-- ============================================================

-- 5) 钓点表
create table if not exists public.spots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  type text not null default '野钓',        -- 野钓 / 路亚 / 黑坑 / 海钓
  description text default '',
  lat double precision not null,
  lng double precision not null,
  rating numeric(2,1) default 0,            -- 评分 0-5
  report_count int default 0,               -- 被报错次数
  verified boolean default false,           -- 官方核实
  created_at timestamptz default now()
);

-- 6) 钓点报错表
create table if not exists public.spot_reports (
  id uuid primary key default gen_random_uuid(),
  spot_id uuid references public.spots(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  reason text not null default '其他',      -- 坐标错误/已关闭/信息有误/已收费/其他
  note text,
  resolved boolean default false,
  created_at timestamptz default now()
);

create index if not exists spots_created_idx on public.spots (created_at desc);
create index if not exists reports_spot_idx on public.spot_reports (spot_id);

-- RLS：钓点公开读，登录可发布；报错公开读，登录可提交
alter table public.spots enable row level security;
alter table public.spot_reports enable row level security;

create policy "spots_read" on public.spots for select using (true);
create policy "spots_insert" on public.spots
  for insert with check (auth.uid() = user_id);
create policy "spots_delete" on public.spots
  for delete using (auth.uid() = user_id);

create policy "reports_read" on public.spot_reports for select using (true);
create policy "reports_insert" on public.spot_reports
  for insert with check (auth.uid() = user_id);
create policy "reports_admin" on public.spot_reports
  for delete using (auth.uid() is not null); -- 后台登录用户可处理

-- 报错数累加函数
create or replace function public.increment_spot_report(sid uuid)
returns void language sql as $$
  update public.spots set report_count = report_count + 1 where id = sid;
$$;
