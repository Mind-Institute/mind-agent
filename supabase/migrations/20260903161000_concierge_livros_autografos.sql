-- Regra operacional do Summit: disponibilidade de livros e autógrafos dos Legends.
--
-- O documento raiz continua sendo a fonte editorial canônica. Esta migration
-- materializa a seção 9 na Intelligence pesquisável e versiona o aviso da Home.
-- O upsert evita duplicar o aviso que já havia sido criado diretamente em produção.

begin;

with evento as (
  select id
  from summit_2026.events
  where slug = 'mind-summit-2026'
), conteudo as (
  select
    md5('summit-2026:livros-autografos')::uuid as id,
    md5('repo:SUMMIT_2026_CANON_AGENTES.md#9-livros-e-autografos')::uuid as fonte_id,
    evento.id as event_id,
    'Livros e autógrafos dos Legends'::text as titulo,
    $doc$Regra oficial para livros e autógrafos no Mind Summit 2026:

- Participantes Prime que queiram garantir um exemplar para assinatura nas sessões exclusivas dos quatro Legends — Amy Edmondson, Jan-Emmanuel De Neve, Christina Maslach e Sonja Lyubomirsky — devem ser orientados a levar o próprio livro.
- A Livraria da Vila terá livros à venda no Summit, mas não há garantia de disponibilidade de títulos, quantidades ou idiomas.
- Livros importados podem estar disponíveis em quantidades extremamente limitadas.
- Jan-Emmanuel De Neve, Christina Maslach e Sonja Lyubomirsky podem não ter livros publicados ou disponíveis no Brasil em volume suficiente.
- Não prometer estoque, título, quantidade, idioma nem a possibilidade de assinatura de item que não seja livro sem confirmação oficial.
- A operação e o estoque dependem da Livraria da Vila. Mesmo com esforço de abastecimento, um título pode acabar.$doc$::text as corpo,
    jsonb_build_object(
      'fonte_canonica', 'SUMMIT_2026_CANON_AGENTES.md',
      'secao', '9. Livros e autógrafos',
      'tags', jsonb_build_array(
        'livros', 'autógrafos', 'Legends', 'Prime', 'Livraria da Vila',
        'estoque', 'livros importados', 'idioma'
      ),
      'autores', jsonb_build_array(
        'Amy Edmondson', 'Jan-Emmanuel De Neve', 'Christina Maslach',
        'Sonja Lyubomirsky'
      ),
      'canon_date', '2026-09-03'
    ) as metadata
  from evento
), documento as (
  insert into summit_2026.knowledge_documents (
    id, fonte_id, titulo, corpo, metadata, hash, atualizado_em,
    tipo_conteudo, problema, resultado_desejado, autor, url, ativo,
    agents, atualizado_em_fonte, aprovado_treble, produto_codigo,
    event_id, valido_de, valido_ate, cluster, audiencia
  )
  select
    id, fonte_id, titulo, corpo, metadata, md5(corpo || metadata::text), now(),
    'regra_evento',
    'A pessoa quer garantir um livro para uma sessão de autógrafos dos Legends.',
    'Orientação segura sobre levar o próprio exemplar e os limites de estoque da livraria.',
    'Mind', null, true, array['concierge']::text[],
    '2026-09-03 00:00:00+00'::timestamptz, true,
    'mind-summit-2026', event_id, null, null, 'produto', 'publico'
  from conteudo
  on conflict (id) do update set
    fonte_id = excluded.fonte_id,
    titulo = excluded.titulo,
    corpo = excluded.corpo,
    metadata = excluded.metadata,
    hash = excluded.hash,
    atualizado_em = now(),
    tipo_conteudo = excluded.tipo_conteudo,
    problema = excluded.problema,
    resultado_desejado = excluded.resultado_desejado,
    autor = excluded.autor,
    url = excluded.url,
    ativo = true,
    agents = excluded.agents,
    atualizado_em_fonte = excluded.atualizado_em_fonte,
    aprovado_treble = true,
    produto_codigo = excluded.produto_codigo,
    event_id = excluded.event_id,
    valido_de = excluded.valido_de,
    valido_ate = excluded.valido_ate,
    cluster = excluded.cluster,
    audiencia = excluded.audiencia
  returning id
)
select id from documento;

-- A lupa híbrida pesquisa chunks, não o corpo bruto do documento. Esta função
-- cria o novo chunk lexical imediatamente e o deixa pendente para embedding.
select public.mind_knowledge_preparar_chunks('summit_2026');

insert into concierge.avisos (
  chave, icone, titulo, subtitulo, descricao, imediato, disparo_em,
  situacao, ver_no_app, botao_ver_no_app, event_id, atualizado_em,
  arquivado_em, categoria
)
select
  'livros_autografos',
  'alerta',
  'Vai aos autógrafos dos Legends? Leve seu livro',
  'A Livraria da Vila terá livros à venda no Summit, mas não podemos garantir a disponibilidade de títulos ou idiomas. Livros importados poderão estar disponíveis em quantidades muito limitadas.',
  'Se você é Prime e quer garantir um exemplar para a assinatura de Jan-Emmanuel De Neve, Christina Maslach, Sonja Lyubomirsky ou Amy Edmondson, recomendamos levar seu próprio livro.',
  false,
  null,
  'no-ar',
  null,
  null,
  id,
  now(),
  null,
  'antes_de_ir'
from summit_2026.events
where slug = 'mind-summit-2026'
on conflict (chave) do update set
  icone = excluded.icone,
  titulo = excluded.titulo,
  subtitulo = excluded.subtitulo,
  descricao = excluded.descricao,
  imediato = excluded.imediato,
  disparo_em = excluded.disparo_em,
  situacao = excluded.situacao,
  ver_no_app = excluded.ver_no_app,
  botao_ver_no_app = excluded.botao_ver_no_app,
  event_id = excluded.event_id,
  atualizado_em = now(),
  arquivado_em = null,
  categoria = excluded.categoria;

do $migration$
begin
  if not exists (
    select 1
    from summit_2026.knowledge_documents
    where id = md5('summit-2026:livros-autografos')::uuid
      and ativo
      and aprovado_treble
      and produto_codigo = 'mind-summit-2026'
      and event_id is not null
  ) then
    raise exception 'documento de livros e autógrafos não foi materializado';
  end if;

  if not exists (
    select 1
    from summit_2026.knowledge_chunks
    where doc_id = md5('summit-2026:livros-autografos')::uuid
      and indice = 'principal'
  ) then
    raise exception 'chunk pesquisável de livros e autógrafos não foi criado';
  end if;

  if not exists (
    select 1
    from concierge.avisos
    where chave = 'livros_autografos'
      and situacao = 'no-ar'
      and categoria = 'antes_de_ir'
      and arquivado_em is null
  ) then
    raise exception 'aviso de livros e autógrafos não foi publicado';
  end if;
end
$migration$;

commit;
