-- Imagem nao e codigo: 9,3 MB de PNG no repositorio do worker seria peso
-- morto e mais uma copia para desencontrar. As fotos vao para um bucket
-- publico, e site, concierge e Treble servem todos pela mesma URL.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('mind-assets', 'mind-assets', true, 5242880,
        array['image/webp','image/png','image/jpeg','image/svg+xml','application/pdf'])
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Leitura publica; escrita so por service role (nenhuma policy de insert).
drop policy if exists "mind-assets leitura publica" on storage.objects;
create policy "mind-assets leitura publica" on storage.objects
  for select to anon, authenticated using (bucket_id = 'mind-assets');

-- Resolve o caminho relativo guardado em asset_path para a URL publica.
-- Enquanto o arquivo nao existir no bucket, devolve o foto_url antigo:
-- ninguem fica sem imagem durante a troca.
create or replace function public.mind_foto_url(p_asset_path text, p_fallback text default null)
returns text
language sql immutable
as $fn$
  select case
    when nullif(p_asset_path,'') is null then p_fallback
    when exists (select 1 from storage.objects o
                  where o.bucket_id = 'mind-assets' and o.name = p_asset_path)
      then 'https://ymnmotgglsrxmjmonwjz.supabase.co/storage/v1/object/public/mind-assets/' || p_asset_path
    else p_fallback
  end;
$fn$;
grant execute on function public.mind_foto_url(text, text) to anon, authenticated;

comment on function public.mind_foto_url(text, text) is
  'URL publica da foto no bucket mind-assets, com fallback para foto_url enquanto o arquivo nao subiu.';

-- asset_path passa a apontar para o webp com o slug de nome completo da
-- planilha (amy-edmondson.webp), nao mais o apelido antigo (amy.webp).
update mind.speakers
   set asset_path = replace(asset_path, '.png', '.webp'), atualizado_em = now()
 where asset_path like '%.png';
