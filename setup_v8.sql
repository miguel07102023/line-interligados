
-- LINE INTERLIGADOS V8 — PATCH FINAL DE HOMOLOGAÇÃO
-- Rode este bloco UMA vez no SQL Editor.

-- 1) Evita duplicar a mesma pessoa/função no mesmo evento.
create unique index if not exists schedules_unique_event_user_role
on public.schedules(event_id, user_id, role_name);

-- 2) Membro atualiza somente o status da própria escala por RPC.
create or replace function public.update_my_schedule_status(
  p_schedule_id bigint,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('confirmed','declined') then
    raise exception 'Status inválido';
  end if;

  update public.schedules
  set status = p_status
  where id = p_schedule_id
    and user_id = auth.uid();
end;
$$;

revoke execute on function public.update_my_schedule_status(bigint,text) from public;
grant execute on function public.update_my_schedule_status(bigint,text) to authenticated;

-- 3) Disponibilidade segura do próprio usuário.
create or replace function public.set_my_availability(
  p_event_id bigint,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_status not in ('available','unavailable','pending') then
    raise exception 'Status inválido';
  end if;

  insert into public.availability(user_id,event_id,status,updated_at)
  values(auth.uid(),p_event_id,p_status,now())
  on conflict(user_id,event_id)
  do update set status=excluded.status, updated_at=now();
end;
$$;

revoke execute on function public.set_my_availability(bigint,text) from public;
grant execute on function public.set_my_availability(bigint,text) to authenticated;

-- 4) Grants do Data API. RLS continua sendo a camada de segurança.
grant select on public.profiles, public.teams, public.member_teams, public.events,
  public.availability, public.schedules, public.notifications, public.activity_logs
to authenticated;

grant insert, update, delete on public.events, public.member_teams, public.schedules,
  public.notifications, public.activity_logs
to authenticated;

grant insert, update, delete on public.availability to authenticated;
grant update on public.profiles to authenticated;

-- 5) Garante leitura de member_teams.
alter table public.member_teams enable row level security;

drop policy if exists "Authenticated users can view member teams" on public.member_teams;
create policy "Authenticated users can view member teams"
on public.member_teams for select to authenticated using (true);

drop policy if exists "Masters can manage member teams" on public.member_teams;
create policy "Masters can manage member teams"
on public.member_teams for all to authenticated
using (public.is_master()) with check (public.is_master());

-- 6) Usuário pode visualizar as próprias escalas; Master visualiza todas.
drop policy if exists "Users view own schedules" on public.schedules;
create policy "Users view own schedules"
on public.schedules for select to authenticated
using (user_id = auth.uid() or public.is_master());

-- 7) Master administra escalas.
drop policy if exists "Masters manage schedules" on public.schedules;
create policy "Masters manage schedules"
on public.schedules for all to authenticated
using (public.is_master()) with check (public.is_master());

-- 8) Notificações.
drop policy if exists "Users view own notifications" on public.notifications;
create policy "Users view own notifications"
on public.notifications for select to authenticated
using (user_id = auth.uid());

drop policy if exists "Users update own notifications" on public.notifications;
create policy "Users update own notifications"
on public.notifications for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "Masters create notifications" on public.notifications;
create policy "Masters create notifications"
on public.notifications for insert to authenticated
with check (public.is_master());

-- 9) Logs administrativos.
drop policy if exists "Masters view activity logs" on public.activity_logs;
create policy "Masters view activity logs"
on public.activity_logs for select to authenticated
using (public.is_master());

drop policy if exists "Masters insert activity logs" on public.activity_logs;
create policy "Masters insert activity logs"
on public.activity_logs for insert to authenticated
with check (public.is_master());
