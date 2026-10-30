-- ============================================================
-- Controle de Envios — MpH Engenharia
-- Banco no Supabase. Cole TUDO no SQL Editor do projeto e clique em Run.
-- Pode rodar de novo sem perder dados (só recria funções e regras).
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- TABELAS ----------------------------------------

-- quem administra (e-mail do login do Supabase Auth)
create table if not exists public.admins (
  email text primary key
);

-- um registro por envio (semana); os lançamentos ficam em "nfs"
create table if not exists public.envios (
  id            text primary key,
  data          date not null,
  obs           text not null default '',
  nfs           jsonb not null default '[]'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- configurações do Controle: pastas das obras, apelidos, importações já feitas
create table if not exists public.config (
  chave         text primary key,
  valor         jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

-- engenheiros com acesso de consulta por PIN
create table if not exists public.engenheiros (
  id        uuid primary key default gen_random_uuid(),
  nome      text not null,
  obras     text[] not null default '{}',
  pin_hash  text,
  ativo     boolean not null default true,
  criado_em timestamptz not null default now()
);

-- registro de tentativas de PIN (para bloquear quem tenta adivinhar)
create table if not exists public.tentativas_pin (
  id  bigserial primary key,
  ip  text not null,
  em  timestamptz not null default now(),
  ok  boolean not null
);
create index if not exists tentativas_pin_ip_em on public.tentativas_pin (ip, em);

-- ---------- QUEM É ADMIN -----------------------------------

create or replace function public.eh_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- ---------- REGRAS DE ACESSO (RLS) -------------------------
-- Só o admin lê e grava as tabelas. Engenheiros não acessam tabela nenhuma:
-- eles só chamam a função consulta_engenheiro, que devolve apenas o que é deles.

alter table public.admins         enable row level security;
alter table public.envios         enable row level security;
alter table public.config         enable row level security;
alter table public.engenheiros    enable row level security;
alter table public.tentativas_pin enable row level security;

drop policy if exists admin_envios      on public.envios;
drop policy if exists admin_config      on public.config;
drop policy if exists admin_engenheiros on public.engenheiros;

create policy admin_envios      on public.envios      for all to authenticated using (public.eh_admin()) with check (public.eh_admin());
create policy admin_config      on public.config      for all to authenticated using (public.eh_admin()) with check (public.eh_admin());
create policy admin_engenheiros on public.engenheiros for all to authenticated using (public.eh_admin()) with check (public.eh_admin());
-- admins e tentativas_pin: sem regra = ninguém lê pela API

revoke all on public.admins, public.tentativas_pin from anon, authenticated;
revoke all on public.envios, public.config, public.engenheiros from anon;
-- permissões explícitas: funciona com ou sem "Automatically expose new tables"
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on public.envios, public.config, public.engenheiros to authenticated;

-- ---------- PIN DOS ENGENHEIROS ----------------------------

-- o admin define o PIN (6 dígitos); fica guardado só o hash
create or replace function public.admin_definir_pin(p_id uuid, p_pin text)
returns void
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not public.eh_admin() then raise exception 'Sem permissão'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{6}$' then raise exception 'O PIN precisa ter 6 dígitos'; end if;
  if public.pin_em_uso(p_pin, p_id) then
    raise exception 'Este PIN já é de outro engenheiro — escolha outro';
  end if;
  update public.engenheiros set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 8)) where id = p_id;
  if not found then raise exception 'Engenheiro não encontrado'; end if;
end;
$$;

-- consulta do engenheiro: confere o PIN e devolve só os lançamentos das obras dele
-- que estão vinculados ou que precisam ser resolvidos (Sem OC, OC Negativada, Falta Apropriação)
create or replace function public.consulta_engenheiro(p_pin text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  v_ip     text;
  v_falhas int;
  v_eng    public.engenheiros;
  r        public.engenheiros;
  v_itens  jsonb;
begin
  v_ip := nullif(trim(split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1)), '');
  v_ip := coalesce(v_ip, 'desconhecido');

  delete from public.tentativas_pin where em < now() - interval '1 day';

  -- 5 PINs errados em 15 minutos no mesmo endereço = bloqueio de 15 minutos
  select count(*) into v_falhas from public.tentativas_pin
   where ip = v_ip and not ok and em > now() - interval '15 minutes';
  if v_falhas >= 5 then
    return jsonb_build_object('erro', 'bloqueado');
  end if;

  if coalesce(p_pin, '') ~ '^[0-9]{6}$' then
    for r in select * from public.engenheiros where ativo and pin_hash is not null loop
      if extensions.crypt(p_pin, r.pin_hash) = r.pin_hash then v_eng := r; exit; end if;
    end loop;
  end if;

  if v_eng.id is null then
    insert into public.tentativas_pin (ip, ok) values (v_ip, false);
    return jsonb_build_object('erro', 'pin', 'restantes', greatest(0, 4 - v_falhas));
  end if;
  insert into public.tentativas_pin (ip, ok) values (v_ip, true);

  select coalesce(jsonb_agg(jsonb_build_object(
           'envio',            e.data,
           'obra',             n ->> 'obra',
           'fase',             n ->> 'fase',
           'fornecedor',       n ->> 'fornecedor',
           'oc',               n ->> 'numero',
           'tipoDoc',          n ->> 'tipoDoc',
           'numDoc',           n ->> 'numDoc',
           'valor',            n -> 'valor',
           'retencao',         coalesce((n ->> 'retencao')::boolean, false),
           'retPct',           n -> 'retPct',
           'vencimento',       n ->> 'vencimento',
           'formaPag',         n ->> 'formaPag',
           'vinculado',        coalesce((n ->> 'vinculado')::boolean, false),
           'semOC',            coalesce((n ->> 'semOC')::boolean, false),
           'ocNegativada',     coalesce((n ->> 'ocNegativada')::boolean, false),
           'faltaApropriacao', coalesce((n ->> 'faltaApropriacao')::boolean, false)
         ) order by e.data desc, n ->> 'vencimento'), '[]'::jsonb)
    into v_itens
    from public.envios e
    cross join lateral jsonb_array_elements(e.nfs) n
   where (n ->> 'obra') = any (v_eng.obras)
     and (   coalesce((n ->> 'vinculado')::boolean, false)
          or coalesce((n ->> 'semOC')::boolean, false)
          or coalesce((n ->> 'ocNegativada')::boolean, false)
          or coalesce((n ->> 'faltaApropriacao')::boolean, false));

  return jsonb_build_object('nome', v_eng.nome, 'obras', to_jsonb(v_eng.obras), 'itens', v_itens);
end;
$$;

-- permissões das funções
revoke all on function public.admin_definir_pin(uuid, text) from public, anon;
grant execute on function public.admin_definir_pin(uuid, text) to authenticated;
revoke all on function public.consulta_engenheiro(text) from public;
grant execute on function public.consulta_engenheiro(text) to anon, authenticated;
grant execute on function public.eh_admin() to authenticated;


-- ---------- CONVITE: o engenheiro cria o próprio PIN ----------
-- O admin gera um link de convite (vale 7 dias, uso único). Quem abre o link escolhe o PIN.
-- Serve para o primeiro acesso e para quem esqueceu o PIN.
alter table public.engenheiros add column if not exists convite_token  text;
alter table public.engenheiros add column if not exists convite_expira timestamptz;
create unique index if not exists engenheiros_convite_token on public.engenheiros (convite_token) where convite_token is not null;

create or replace function public.pin_em_uso(p_pin text, p_exceto uuid)
returns boolean
language plpgsql stable security definer
set search_path = public, extensions
as $$
declare r record;
begin
  for r in select pin_hash from public.engenheiros where id is distinct from p_exceto and pin_hash is not null loop
    if extensions.crypt(p_pin, r.pin_hash) = r.pin_hash then return true; end if;
  end loop;
  return false;
end;
$$;

create or replace function public.admin_gerar_convite(p_id uuid)
returns text
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_token text;
begin
  if not public.eh_admin() then raise exception 'Sem permissão'; end if;
  v_token := encode(extensions.gen_random_bytes(18), 'hex');
  update public.engenheiros set convite_token = v_token, convite_expira = now() + interval '7 days' where id = p_id;
  if not found then raise exception 'Engenheiro não encontrado'; end if;
  return v_token;
end;
$$;

-- a página do convite mostra o nome de quem vai criar o PIN
create or replace function public.ver_convite(p_token text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select jsonb_build_object('nome', nome) from public.engenheiros
      where convite_token = p_token and convite_expira > now() and ativo),
    jsonb_build_object('erro', 'convite'));
$$;

create or replace function public.criar_pin_convite(p_token text, p_pin text)
returns jsonb
language plpgsql security definer
set search_path = public, extensions
as $$
declare v_eng public.engenheiros; v_ip text; v_falhas int;
begin
  v_ip := coalesce(nullif(trim(split_part(coalesce(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ''), ',', 1)), ''), 'desconhecido');
  select count(*) into v_falhas from public.tentativas_pin
   where ip = v_ip and not ok and em > now() - interval '15 minutes';
  if v_falhas >= 5 then return jsonb_build_object('erro', 'bloqueado'); end if;
  select * into v_eng from public.engenheiros
   where convite_token = p_token and convite_expira > now() and ativo;
  if v_eng.id is null then
    insert into public.tentativas_pin (ip, ok) values (v_ip, false);
    return jsonb_build_object('erro', 'convite');
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{6}$' then return jsonb_build_object('erro', 'formato'); end if;
  -- PIN repetido conta como tentativa: impede usar o convite para descobrir o PIN de outra pessoa
  if public.pin_em_uso(p_pin, v_eng.id) then
    insert into public.tentativas_pin (ip, ok) values (v_ip, false);
    return jsonb_build_object('erro', 'em_uso');
  end if;
  update public.engenheiros
     set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 8)), convite_token = null, convite_expira = null
   where id = v_eng.id;
  return jsonb_build_object('ok', true, 'nome', v_eng.nome);
end;
$$;

revoke all on function public.pin_em_uso(text, uuid) from public, anon, authenticated;
revoke all on function public.admin_gerar_convite(uuid) from public, anon;
grant execute on function public.admin_gerar_convite(uuid) to authenticated;
revoke all on function public.ver_convite(text) from public;
grant execute on function public.ver_convite(text) to anon, authenticated;
revoke all on function public.criar_pin_convite(text, text) from public;
grant execute on function public.criar_pin_convite(text, text) to anon, authenticated;

-- ============================================================
-- DEPOIS DE RODAR: o seu acesso de admin é um usuário do Supabase Auth
-- com o e-mail que está no config.js e o seu PIN de admin (8 dígitos) como senha.
-- Cadastre esse e-mail como admin (troque e rode só esta linha):
--
--   insert into public.admins (email) values ('admin@controle-mph.local');
-- ============================================================
