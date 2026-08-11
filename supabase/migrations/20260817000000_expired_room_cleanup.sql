create extension if not exists pg_cron with schema pg_catalog;

create or replace function private.cleanup_expired_rooms(
  p_batch_size integer default 500
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted_count integer;
begin
  if p_batch_size < 1 or p_batch_size > 5000 then
    raise exception using
      errcode = '22023',
      message = 'cleanup_batch_size_invalid';
  end if;

  with expired_rooms as (
    select room.id
    from public.rooms as room
    where room.expires_at <= statement_timestamp()
    order by room.expires_at, room.id
    limit p_batch_size
    for update skip locked
  ), deleted_rooms as (
    delete from public.rooms as room
    using expired_rooms
    where room.id = expired_rooms.id
    returning room.id
  )
  select count(*)::integer
  into v_deleted_count
  from deleted_rooms;

  return v_deleted_count;
end;
$$;
revoke all on function private.cleanup_expired_rooms(integer) from public;
revoke all on function private.cleanup_expired_rooms(integer) from anon;
revoke all on function private.cleanup_expired_rooms(integer) from authenticated;

comment on function private.cleanup_expired_rooms(integer) is
  'Deletes expired rooms in bounded batches. Related players, turns, draws, and deck state are removed through foreign-key cascades.';

do $$
declare
  v_existing_job_id bigint;
begin
  select job.jobid
  into v_existing_job_id
  from cron.job as job
  where job.jobname = 'cleanup-expired-rooms-hourly';

  if v_existing_job_id is not null then
    perform cron.unschedule(v_existing_job_id);
  end if;

  perform cron.schedule(
    'cleanup-expired-rooms-hourly',
    '7 * * * *',
    'select private.cleanup_expired_rooms(500);'
  );
end;
$$;
