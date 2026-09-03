-- Concierge Summit: memoria em camadas sem inflar o prompt.
--
-- Menor mudanca suficiente:
--   1. o kit permanente resolve o evento pedido e inclui somente regras criticas;
--   2. buscar/ler passam a cobrir todas as casas factuais do Summit;
--   3. a regra operacional de livros/autografos entra em event_rules;
--   4. o lembrete correspondente entra em concierge.avisos;
--   5. o playbook continua sem fatos mutaveis e nenhuma fonte paralela e criada.

create or replace function public.mind_intelligence_buscar(
  p_necessidade text,
  p_limite      int default 6
) returns jsonb
language sql stable security definer
set search_path to 'public', 'summit_2026', 'ecossistema', 'concierge'
as $function$
  with
  lim as (
    select least(10, greatest(1, coalesce(p_limite, 6))) as n
  ),
  alvo as (
    select e.*
    from summit_2026.events e
    where e.slug = 'mind-summit-2026' and e.ativo
    limit 1
  ),
  foco as (
    select nullif(string_agg(quote_literal(l.lexeme), ' | '), '')::tsquery as q
    from unnest(to_tsvector(
      'portuguese',
      coalesce(nullif(btrim(p_necessidade), ''), 'programacao')
    )) l
  ),
  busca as (
    select public.mindagent_chat_search(
      'mind-summit-2026',
      coalesce(nullif(btrim(p_necessidade), ''), 'programacao'),
      (select n from lim)
    ) as s
  ),
  pessoas as (
    select jsonb_build_object(
      'tipo', 'palestrante',
      'id', e->>'id',
      'titulo', e->>'name',
      'resumo', nullif(concat_ws(' · ', nullif(e->>'role', ''), nullif(e->>'organization', '')), ''),
      'event_slug', 'mind-summit-2026'
    ) as c, 0.10::real as score
    from busca, jsonb_array_elements(busca.s->'speakers') e
  ),
  sessoes as (
    select jsonb_build_object(
      'tipo', 'sessao',
      'id', e->>'id',
      'titulo', e->>'title',
      'resumo', nullif(concat_ws(
        ' · ',
        nullif(e->>'type', ''),
        nullif(e->>'starts_at_local', '') || '–' || nullif(e->>'ends_at_local', ''),
        nullif(e->>'location', '')
      ), ''),
      'ingressos', coalesce(e->'ingressos', '[]'::jsonb),
      'event_slug', 'mind-summit-2026'
    ) as c, 0.10::real as score
    from busca, jsonb_array_elements(busca.s->'sessions') e
  ),
  conhecimento as (
    select jsonb_build_object(
      'tipo', 'conhecimento',
      'id', k.id::text,
      'titulo', k.titulo,
      'resumo', nullif(concat_ws(' · ', nullif(k.tipo_conteudo, ''), left(k.corpo, 180)), ''),
      'vigencia', jsonb_strip_nulls(jsonb_build_object('de', k.valido_de, 'ate', k.valido_ate)),
      'event_slug', a.slug
    ) as c,
    (0.15 + ts_rank_cd(
      to_tsvector('portuguese', coalesce(k.tipo_conteudo, '') || ' ' || k.titulo || ' ' || k.corpo),
      f.q
    ))::real as score
    from summit_2026.knowledge_documents k
    cross join alvo a
    cross join foco f
    where f.q is not null
      and k.ativo
      and 'concierge' = any(k.agents)
      and (k.event_id is null or k.event_id = a.id)
      and (k.produto_codigo is null or k.produto_codigo = a.produto_codigo)
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())
      and to_tsvector('portuguese', coalesce(k.tipo_conteudo, '') || ' ' || k.titulo || ' ' || k.corpo) @@ f.q
    order by score desc, k.titulo
    limit (select n from lim)
  ),
  regras as (
    select jsonb_build_object(
      'tipo', 'regra_evento',
      'id', r.chave,
      'titulo', r.titulo,
      'resumo', left(r.texto, 220),
      'aplica_em', r.aplica_em,
      'prioridade', r.prioridade,
      'event_slug', a.slug
    ) as c,
    (0.30 + ts_rank_cd(
      to_tsvector('portuguese', r.chave || ' ' || r.titulo || ' ' || r.texto || ' ' || array_to_string(r.aplica_em, ' ')),
      f.q
    ))::real as score
    from summit_2026.event_rules r
    cross join alvo a
    cross join foco f
    where f.q is not null
      and r.ativo
      and r.event_id = a.id
      and to_tsvector('portuguese', r.chave || ' ' || r.titulo || ' ' || r.texto || ' ' || array_to_string(r.aplica_em, ' ')) @@ f.q
    order by score desc, r.prioridade, r.titulo
    limit (select n from lim)
  ),
  avisos as (
    select jsonb_build_object(
      'tipo', 'aviso',
      'id', v.id::text,
      'titulo', v.titulo,
      'resumo', left(concat_ws(' ', v.subtitulo, v.descricao), 220),
      'categoria', v.categoria,
      'vigencia', jsonb_strip_nulls(jsonb_build_object('disparo_em', v.disparo_em, 'situacao', v.situacao)),
      'event_slug', a.slug
    ) as c,
    (0.25 + ts_rank_cd(
      to_tsvector('portuguese', v.chave || ' ' || v.titulo || ' ' || coalesce(v.subtitulo, '') || ' ' || coalesce(v.descricao, '')),
      f.q
    ))::real as score
    from concierge.avisos v
    cross join alvo a
    cross join foco f
    where f.q is not null
      and v.arquivado_em is null
      and (v.event_id is null or v.event_id = a.id)
      and (v.situacao = 'no-ar' or (v.situacao = 'agendado' and v.disparo_em <= now()))
      and to_tsvector('portuguese', v.chave || ' ' || v.titulo || ' ' || coalesce(v.subtitulo, '') || ' ' || coalesce(v.descricao, '')) @@ f.q
    order by score desc, v.atualizado_em desc
    limit (select n from lim)
  ),
  locais as (
    select jsonb_build_object(
      'tipo', 'local',
      'id', l.id::text,
      'titulo', l.nome,
      'resumo', nullif(concat_ws(' · ', nullif(l.tipo, ''), nullif(l.andar, ''), nullif(l.descricao, ''), nullif(l.como_chegar, '')), ''),
      'event_slug', a.slug
    ) as c,
    (0.12 + ts_rank_cd(
      to_tsvector('portuguese', l.nome || ' ' || coalesce(l.slug, '') || ' ' || coalesce(array_to_string(l.aliases, ' '), '') || ' ' || coalesce(l.descricao, '') || ' ' || coalesce(l.como_chegar, '')),
      f.q
    ))::real as score
    from summit_2026.locations l
    cross join alvo a
    cross join foco f
    where f.q is not null
      and l.ativo
      and l.event_id = a.id
      and to_tsvector('portuguese', l.nome || ' ' || coalesce(l.slug, '') || ' ' || coalesce(array_to_string(l.aliases, ' '), '') || ' ' || coalesce(l.descricao, '') || ' ' || coalesce(l.como_chegar, '')) @@ f.q
    order by score desc, l.nome
    limit (select n from lim)
  ),
  expositores as (
    select jsonb_build_object(
      'tipo', 'expositor',
      'id', x.id::text,
      'titulo', x.nome,
      'resumo', nullif(concat_ws(' · ', nullif(x.categoria, ''), nullif(x.descricao, ''), nullif(l.nome, '')), ''),
      'event_slug', a.slug
    ) as c,
    (0.12 + ts_rank_cd(
      to_tsvector('portuguese', x.nome || ' ' || coalesce(x.slug, '') || ' ' || coalesce(x.categoria, '') || ' ' || coalesce(x.descricao, '') || ' ' || coalesce(l.nome, '')),
      f.q
    ))::real as score
    from summit_2026.exhibitors x
    cross join alvo a
    cross join foco f
    left join summit_2026.locations l on l.id = x.location_id
    where f.q is not null
      and x.ativo
      and x.event_id = a.id
      and to_tsvector('portuguese', x.nome || ' ' || coalesce(x.slug, '') || ' ' || coalesce(x.categoria, '') || ' ' || coalesce(x.descricao, '') || ' ' || coalesce(l.nome, '')) @@ f.q
    order by score desc, x.nome
    limit (select n from lim)
  ),
  todos as (
    select c, score from pessoas
    union all select c, score from sessoes
    union all select c, score from conhecimento
    union all select c, score from regras
    union all select c, score from avisos
    union all select c, score from locais
    union all select c, score from expositores
  )
  select jsonb_build_object(
    'necessidade', p_necessidade,
    'event_slug', 'mind-summit-2026',
    'candidatos', coalesce(
      (select jsonb_agg(c order by score desc, c->>'tipo', c->>'titulo') from todos),
      '[]'::jsonb
    ),
    'total', (select count(*) from todos),
    'como_usar', 'Cada candidato tem tipo e id. Leia os objetos relevantes com ler_intelligence(tipo, id). Combine fontes quando a pergunta exigir, por exemplo sessao + regra de acesso + aviso. Se nada responder, reformule uma vez; nao complete com conhecimento proprio.'
  );
$function$;

create or replace function public.mind_intelligence_ler(
  p_tipo  text,
  p_id    text,
  p_corte int default 1200
) returns jsonb
language sql stable security definer
set search_path to 'public', 'summit_2026', 'ecossistema', 'concierge'
as $function$
  select case lower(coalesce(p_tipo, ''))
    when 'palestrante' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','palestrante','id', sp.id,'nome', sp.nome,'cargo', sp.cargo_curto,
        'instituicao', sp.instituicao,
        'quem_e', public.mind_txt_corta(sp.quem_e, n.v),
        'formacao_e_posicao', public.mind_txt_corta(sp.formacao_e_posicao, n.v),
        'principais_contribuicoes', public.mind_txt_corta(sp.principais_contribuicoes, n.v),
        'conceitos_chave_explicados', public.mind_txt_corta(sp.conceitos_chave_explicados, n.v),
        'por_que_o_conteudo_e_importante', public.mind_txt_corta(sp.por_que_o_conteudo_e_importante, n.v),
        'o_que_posso_esperar_ouvir_e_aprender', public.mind_txt_corta(sp.o_que_posso_esperar_ouvir_e_aprender, n.v),
        'dores_e_problemas_que_ajuda_a_compreender', public.mind_txt_corta(sp.dores_e_problemas_que_ajuda_a_compreender, n.v),
        'relevancia_para_os_icps_do_mind', public.mind_txt_corta(sp.relevancia_para_os_icps_do_mind, n.v),
        'principais_livros', public.mind_txt_corta(sp.principais_livros, n.v),
        'principais_papers', public.mind_txt_corta(sp.principais_papers, n.v),
        'limites_e_cuidados_cientificos', public.mind_txt_corta(sp.limites_e_cuidados_cientificos, n.v),
        'sessoes', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', s.id,'titulo', s.titulo,'tipo', s.tipo,'dia', s.dia,
            'inicio', to_char(s.inicio at time zone e.fuso,'HH24:MI'),
            'fim', to_char(s.fim at time zone e.fuso,'HH24:MI'),
            'local', l.nome,'participacao', ss.papel
          ) order by s.inicio)
          from summit_2026.session_speakers ss
          join summit_2026.sessions s on s.id = ss.sessao_id
          join summit_2026.events e on e.id = s.event_id and e.slug = 'mind-summit-2026' and e.ativo
          left join summit_2026.locations l on l.id = s.espaco_id
          where ss.speaker_id = sp.id
        ), '[]'::jsonb)
      ))
      from ecossistema.palestrantes_especialistas sp
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where sp.id::text = p_id or sp.slug = p_id
      limit 1
    )
    when 'sessao' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','sessao','id', s.id,'titulo', s.titulo,
        'descricao', public.mind_txt_corta(s.descricao, n.v),
        'formato', s.formato,'nivel', s.nivel,'trilhas', s.trilhas,
        'topicos_aprendizado', s.topicos_aprendizado,'resultados', s.resultados,
        'dia', s.dia,'inicio', to_char(s.inicio at time zone e.fuso,'HH24:MI'),
        'fim', to_char(s.fim at time zone e.fuso,'HH24:MI'),'fuso', e.fuso,
        'local', l.nome,'tipo_de_sessao', s.tipo,'precisa_reserva', s.precisa_reserva,
        'lugares_limitados', s.lugares_limitados,'reserva_recomendada', s.reserva_recomendada,
        'ingressos', s.ingressos,
        'palestrantes', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', sp.id,'nome', sp.nome,'cargo', sp.cargo_curto,
            'instituicao', sp.instituicao,'participacao', ss.papel
          ) order by sp.nome)
          from summit_2026.session_speakers ss
          join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
          where ss.sessao_id = s.id
        ), '[]'::jsonb)
      ))
      from summit_2026.sessions s
      join summit_2026.events e on e.id = s.event_id and e.slug = 'mind-summit-2026' and e.ativo
      left join summit_2026.locations l on l.id = s.espaco_id
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where s.id::text = p_id
      limit 1
    )
    when 'conhecimento' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','conhecimento','id', k.id,'titulo', k.titulo,'categoria', k.tipo_conteudo,
        'problema', k.problema,'resultado_desejado', k.resultado_desejado,
        'audiencia', k.audiencia,'cluster', k.cluster,
        'corpo', public.mind_txt_corta(k.corpo, n.v * 3),
        'autor', k.autor,'url', k.url,
        'vigencia', jsonb_strip_nulls(jsonb_build_object('de', k.valido_de, 'ate', k.valido_ate))
      ))
      from summit_2026.knowledge_documents k
      join summit_2026.events e on (k.event_id is null or k.event_id = e.id)
        and e.slug = 'mind-summit-2026' and e.ativo
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where k.id::text = p_id
        and k.ativo and 'concierge' = any(k.agents)
        and (k.produto_codigo is null or k.produto_codigo = e.produto_codigo)
        and (k.valido_de is null or k.valido_de <= now())
        and (k.valido_ate is null or k.valido_ate > now())
      limit 1
    )
    when 'regra_evento' then (
      select jsonb_build_object(
        'tipo','regra_evento','id', r.chave,'titulo', r.titulo,'texto', r.texto,
        'aplica_em', r.aplica_em,'prioridade', r.prioridade,
        'event_slug', e.slug,'atualizado_em', r.atualizado_em
      )
      from summit_2026.event_rules r
      join summit_2026.events e on e.id = r.event_id and e.slug = 'mind-summit-2026' and e.ativo
      where r.chave = p_id and r.ativo
      limit 1
    )
    when 'aviso' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','aviso','id', v.id,'chave', v.chave,'titulo', v.titulo,
        'subtitulo', v.subtitulo,'descricao', v.descricao,'categoria', v.categoria,
        'situacao', v.situacao,'disparo_em', v.disparo_em,
        'ver_no_app', v.ver_no_app,'botao_ver_no_app', v.botao_ver_no_app,
        'event_slug', e.slug,'atualizado_em', v.atualizado_em
      ))
      from concierge.avisos v
      join summit_2026.events e on (v.event_id is null or v.event_id = e.id)
        and e.slug = 'mind-summit-2026' and e.ativo
      where v.id::text = p_id
        and v.arquivado_em is null
        and (v.situacao = 'no-ar' or (v.situacao = 'agendado' and v.disparo_em <= now()))
      limit 1
    )
    when 'local' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','local','id', l.id,'nome', l.nome,'slug', l.slug,'aliases', l.aliases,
        'categoria', l.tipo,'descricao', public.mind_txt_corta(l.descricao, n.v),
        'andar', l.andar,'como_chegar', public.mind_txt_corta(l.como_chegar, n.v),
        'coordenadas_mapa', l.coordenadas_mapa,'acessibilidade', l.acessibilidade,
        'local_pai', p.nome,'event_slug', e.slug
      ))
      from summit_2026.locations l
      join summit_2026.events e on e.id = l.event_id and e.slug = 'mind-summit-2026' and e.ativo
      left join summit_2026.locations p on p.id = l.parent_id
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where l.id::text = p_id and l.ativo
      limit 1
    )
    when 'expositor' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','expositor','id', x.id,'nome', x.nome,'slug', x.slug,
        'categoria', x.categoria,'descricao', public.mind_txt_corta(x.descricao, n.v),
        'site_url', x.site_url,'contato', x.contato,'local', l.nome,
        'event_slug', e.slug,'atualizado_em', x.atualizado_em
      ))
      from summit_2026.exhibitors x
      join summit_2026.events e on e.id = x.event_id and e.slug = 'mind-summit-2026' and e.ativo
      left join summit_2026.locations l on l.id = x.location_id
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where x.id::text = p_id and x.ativo
      limit 1
    )
    else null
  end;
$function$;

create or replace function public.mind_kit_evento(
  p_conversa_id uuid default null,
  p_necessidade jsonb default null
) returns jsonb
language sql stable security definer
set search_path to 'public', 'summit_2026', 'catalogo', 'concierge'
as $function$
  with
  alvo as (
    select coalesce(
      nullif(btrim(coalesce(p_necessidade->>'event_slug', '')), ''),
      'mind-summit-2026'
    ) as slug
  ),
  evento as (
    select e.*
    from summit_2026.events e
    cross join alvo a
    where e.slug = a.slug and e.ativo
    limit 1
  ),
  produto as (
    select p.*
    from catalogo.produtos p
    join evento e on p.codigo = e.produto_codigo
  ),
  avisos_importantes as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'chave', a.chave,'icone', a.icone,'titulo', a.titulo,
        'subtitulo', a.subtitulo,'descricao', a.descricao,
        'categoria', a.categoria,'situacao', a.situacao,
        'disparo_em', a.disparo_em,'ver_no_app', a.ver_no_app,
        'botao_ver_no_app', a.botao_ver_no_app
      ) order by a.imediato desc, a.disparo_em desc nulls last, a.atualizado_em desc
    ), '[]'::jsonb) as itens
    from concierge.avisos a
    cross join evento e
    where a.arquivado_em is null
      and (a.event_id is null or a.event_id = e.id)
      and (a.situacao = 'no-ar' or (a.situacao = 'agendado' and a.disparo_em <= now()))
  ),
  regras_criticas as (
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'chave', r.chave,'titulo', r.titulo,'texto', r.texto,
        'aplica_em', r.aplica_em,'prioridade', r.prioridade
      ) order by r.prioridade, r.titulo
    ), '[]'::jsonb) as itens
    from summit_2026.event_rules r
    cross join evento e
    where r.ativo and r.event_id = e.id and r.prioridade <= 2
  )
  select case
    when not exists (select 1 from evento) then null::jsonb
    when not exists (select 1 from produto) then null::jsonb
    else jsonb_build_object(
      'bloco', 'evento',
      'event_slug', (select slug from evento),
      'evento', (select to_jsonb(e) - 'id' from evento e),
      'produto', (select jsonb_build_object(
        'codigo', p.codigo,'nome', p.nome,'tipo', p.tipo,
        'vertical', p.vertical,'ativo', p.ativo,'vende', p.vende
      ) from produto p),
      'regras_criticas', (select itens from regras_criticas),
      'avisos_importantes', (select itens from avisos_importantes)
    )
  end;
$function$;

insert into summit_2026.event_rules (
  chave, titulo, texto, aplica_em, prioridade, ativo, atualizado_em, event_id
)
select
  'livros-autografos',
  'Livros para os autografos dos Legends',
  'Recomendar que participantes Prime levem seus proprios exemplares se quiserem garantir um livro para assinatura dos Legends. A Livraria da Vila tera livros para venda, mas a disponibilidade nao e garantida. Livros importados podem existir em quantidades extremamente limitadas. Jan-Emmanuel De Neve, Christina Maslach e Sonja Lyubomirsky podem nao ter livros publicados ou disponiveis no Brasil em volume suficiente. Nao prometer estoque, titulo, quantidade, idioma ou possibilidade de assinatura de item que nao seja livro sem confirmacao oficial. A operacao e o estoque dependem da Livraria da Vila; mesmo com esforco de abastecimento, um titulo pode acabar.',
  array['autografos','livros','prime','livraria'],
  2,
  true,
  now(),
  e.id
from summit_2026.events e
where e.slug = 'mind-summit-2026' and e.ativo
on conflict (chave) do update set
  titulo = excluded.titulo,
  texto = excluded.texto,
  aplica_em = excluded.aplica_em,
  prioridade = excluded.prioridade,
  ativo = excluded.ativo,
  atualizado_em = excluded.atualizado_em,
  event_id = excluded.event_id;

insert into concierge.avisos (
  id, chave, icone, titulo, subtitulo, descricao, imediato,
  situacao, event_id, categoria, criado_em, atualizado_em
)
select
  gen_random_uuid(),
  'livros_autografos',
  'estrela',
  'Leve seu livro para os autografos dos Legends',
  'Se voce e Prime e quer garantir um exemplar para assinatura, recomendamos levar o seu proprio livro.',
  'A Livraria da Vila tera livros a venda, mas o estoque nao e garantido. Livros importados podem estar disponiveis em quantidades muito limitadas, e alguns Legends podem nao ter titulos publicados ou disponiveis no Brasil em volume suficiente. Nao conte com titulo, idioma ou quantidade especificos.',
  false,
  'no-ar',
  e.id,
  'antes_de_ir',
  now(),
  now()
from summit_2026.events e
where e.slug = 'mind-summit-2026' and e.ativo
on conflict (chave) do update set
  icone = excluded.icone,
  titulo = excluded.titulo,
  subtitulo = excluded.subtitulo,
  descricao = excluded.descricao,
  imediato = excluded.imediato,
  situacao = excluded.situacao,
  event_id = excluded.event_id,
  categoria = excluded.categoria,
  arquivado_em = null,
  atualizado_em = excluded.atualizado_em;

update concierge.ferramentas
set
  descricao = case nome
    when 'buscar_intelligence' then
      'Procura em toda a Intelligence aprovada do Mind Summit: palestrantes, sessoes, Knowledge Documents, regras, avisos, locais e expositores. Formule a necessidade nos termos do dominio. Devolve candidatos compactos com tipo e id; combine mais de uma fonte quando a pergunta exigir.'
    when 'ler_intelligence' then
      'Abre em profundidade um objeto encontrado por buscar_intelligence. Use tipo e id exatamente como devolvidos e leia todos os objetos necessarios antes de responder perguntas que combinem sessao, acesso, regra, aviso ou local.'
  end,
  json_schema = case nome
    when 'buscar_intelligence' then jsonb_build_object(
      'type','object',
      'required',jsonb_build_array('necessidade','limite'),
      'properties',jsonb_build_object(
        'necessidade',jsonb_build_object(
          'type','string',
          'description','A necessidade traduzida para os termos do dominio, nao apenas a frase crua da pessoa.'
        ),
        'limite',jsonb_build_object(
          'type',jsonb_build_array('integer','null'),
          'description','Quantos candidatos por familia de fonte, de 1 a 10. null usa o padrao.'
        )
      ),
      'additionalProperties',false
    )
    when 'ler_intelligence' then jsonb_build_object(
      'type','object',
      'required',jsonb_build_array('tipo','id'),
      'properties',jsonb_build_object(
        'tipo',jsonb_build_object(
          'type','string',
          'enum',jsonb_build_array(
            'palestrante','sessao','conhecimento','regra_evento','aviso','local','expositor'
          ),
          'description','O tipo devolvido por buscar_intelligence.'
        ),
        'id',jsonb_build_object(
          'type','string',
          'description','O id devolvido por buscar_intelligence.'
        )
      ),
      'additionalProperties',false
    )
  end,
  versao = greatest(coalesce(versao, 1), 2)
where nome in ('buscar_intelligence','ler_intelligence');

comment on function public.mind_intelligence_buscar(text, int) is
  'Busca unificada e somente-leitura do Concierge nas casas canonicas do Mind Summit 2026: palestrantes, sessoes, knowledge_documents, event_rules, avisos, locations e exhibitors. Nao cria fonte paralela.';

comment on function public.mind_intelligence_ler(text, text, int) is
  'Leitura profunda por tipo+id dos objetos devolvidos pela busca unificada. Respeita evento ativo, visibilidade, vigencia e corte de campos longos.';

comment on function public.mind_kit_evento(uuid, jsonb) is
  'Contexto permanente enxuto do evento pedido: evento+produto correspondentes, regras criticas e avisos vigentes. Resolve por p_necessidade.event_slug; NULL quando evento ou produto nao existem.';

revoke all on function public.mind_intelligence_buscar(text, int) from public, anon, authenticated;
revoke all on function public.mind_intelligence_ler(text, text, int) from public, anon, authenticated;
revoke all on function public.mind_kit_evento(uuid, jsonb) from public, anon, authenticated;

grant execute on function public.mind_intelligence_buscar(text, int) to service_role;
grant execute on function public.mind_intelligence_ler(text, text, int) to service_role;
grant execute on function public.mind_kit_evento(uuid, jsonb) to service_role;
