-- Contrato pós-migração: a regra precisa existir na Intelligence, ser recuperável
-- no App e no WhatsApp e continuar aparecendo como um único aviso vivo na Home.
--
-- Como rodar: psql "$DATABASE_URL" -f tests/concierge_livros_autografos_contract.sql

begin;

do $test$
declare
  v_doc_id constant uuid := md5('summit-2026:livros-autografos')::uuid;
  v_app jsonb;
  v_whatsapp jsonb;
begin
  if (
    select count(*)
    from summit_2026.knowledge_documents
    where id = v_doc_id
      and ativo
      and audiencia = 'publico'
      and 'concierge' = any(agents)
      and aprovado_treble
  ) <> 1 then
    raise exception 'documento canônico ausente, duplicado ou fora do escopo';
  end if;

  if (
    select count(*)
    from summit_2026.knowledge_chunks
    where doc_id = v_doc_id and indice = 'principal'
  ) <> 1 then
    raise exception 'chunk principal ausente ou duplicado';
  end if;

  if not exists (
    select 1
    from summit_2026.knowledge_chunks
    where doc_id = v_doc_id
      and tsv @@ plainto_tsquery('portuguese', 'livros importados Livraria da Vila')
  ) then
    raise exception 'chunk não indexa estoque, importados e Livraria da Vila';
  end if;

  if (
    select count(*)
    from concierge.avisos
    where chave = 'livros_autografos'
      and titulo = 'Vai aos autógrafos dos Legends? Leve seu livro'
      and situacao = 'no-ar'
      and categoria = 'antes_de_ir'
      and arquivado_em is null
  ) <> 1 then
    raise exception 'aviso vivo ausente, duplicado ou divergente';
  end if;

  v_app := public.mind_intelligence_buscar_contextual(
    'livros importados Livraria da Vila', 10,
    'concierge_summit', 'app', 'mind-summit-2026', null
  );

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_app->'candidatos', '[]'::jsonb)) candidato
    where candidato->>'id' = 'summit_2026:' || v_doc_id::text
  ) then
    raise exception 'lupa do App não recuperou a regra: %', v_app;
  end if;

  v_whatsapp := public.mind_intelligence_buscar_contextual(
    'levar próprio livro autógrafos Legends', 10,
    'summit_b2c', 'whatsapp', 'mind-summit-2026', null
  );

  if not exists (
    select 1
    from jsonb_array_elements(coalesce(v_whatsapp->'candidatos', '[]'::jsonb)) candidato
    where candidato->>'id' = 'summit_2026:' || v_doc_id::text
  ) then
    raise exception 'lupa do WhatsApp não recuperou a regra: %', v_whatsapp;
  end if;
end
$test$;

rollback;
