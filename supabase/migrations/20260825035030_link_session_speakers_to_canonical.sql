-- Torna ecossistema.palestrantes_especialistas a fonte da verdade "linkável"
-- e liga summit_2026.session_speakers a ela. Mudança ADITIVA e reversível:
-- nada é dropado; palestrante_id (uuid antigo) permanece durante a transição.

--------------------------------------------------------------------------
-- 1) Chave estável na canônica: slug + auto-slug + guardas anti-duplicado
--------------------------------------------------------------------------
alter table ecossistema.palestrantes_especialistas
  add column if not exists slug text;

create or replace function ecossistema.slugify(txt text)
returns text
language sql
immutable
security invoker
set search_path = pg_catalog
as $fn$
  select trim(both '-' from
    regexp_replace(
      translate(
        lower(coalesce(txt, '')),
        'áàâãäéèêëíìîïóòôõöúùûüçñ',
        'aaaaaeeeeiiiiooooouuuucn'
      ),
      '[^a-z0-9]+', '-', 'g'
    )
  );
$fn$;

-- backfill dos registros existentes
update ecossistema.palestrantes_especialistas
   set slug = ecossistema.slugify(nome)
 where slug is null or slug = '';

-- trigger: novo speaker sem slug recebe slug do nome automaticamente
create or replace function ecossistema.palestrantes_slug_bi()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $tg$
begin
  if new.slug is null or new.slug = '' then
    new.slug := ecossistema.slugify(new.nome);
  end if;
  return new;
end;
$tg$;

drop trigger if exists trg_palestrantes_slug on ecossistema.palestrantes_especialistas;
create trigger trg_palestrantes_slug
  before insert or update on ecossistema.palestrantes_especialistas
  for each row execute function ecossistema.palestrantes_slug_bi();

create unique index if not exists palestrantes_slug_uidx
  on ecossistema.palestrantes_especialistas (slug);
create unique index if not exists palestrantes_nome_uidx
  on ecossistema.palestrantes_especialistas (lower(btrim(nome)));

--------------------------------------------------------------------------
-- 2) Ligação: session_speakers -> canônica (coluna nova, nullable, com FK)
--    palestrante_id (uuid antigo) NÃO é alterado nem removido.
--------------------------------------------------------------------------
alter table summit_2026.session_speakers
  add column if not exists speaker_id bigint;

alter table summit_2026.session_speakers
  drop constraint if exists session_speakers_speaker_id_fkey;
alter table summit_2026.session_speakers
  add constraint session_speakers_speaker_id_fkey
  foreign key (speaker_id)
  references ecossistema.palestrantes_especialistas (id)
  on delete set null;

create index if not exists session_speakers_speaker_id_idx
  on summit_2026.session_speakers (speaker_id);
