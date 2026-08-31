-- buscar_intelligence / ler_intelligence: o Agent passa a investigar a Intelligence
-- durante o proprio turno, em vez de receber um contexto fixo e torcer para bastar.
--
-- POR QUE ISTO EXISTE. Hoje o sistema escolhe o contexto ANTES de o modelo pensar:
-- `mindagent_chat_search` recebe a frase crua do lead, e o que voltar e o que o Agent
-- tem. Quando a pergunta e "quem vai subir no palco?", nenhuma palavra casa com o dado,
-- o bloco volta vazio e o agente diz -- com honestidade -- que nao sabe. O ganho aqui
-- NAO e um motor de busca melhor: e QUEM FORMULA A CONSULTA passar a ser o modelo, que
-- sabe transformar aquilo em "palestrantes Mind Summit 2026". Medido: a frase crua
-- devolvia 0 candidatos; a consulta formulada devolve 6.
--
-- NENHUMA FONTE NOVA DA VERDADE. Palestrante continua em
-- `ecossistema.palestrantes_especialistas`, sessao em `summit_2026.sessions`,
-- conhecimento em `summit_2026.knowledge_documents`. Estas funcoes LEEM essas casas;
-- nao copiam, nao indexam a parte, nao criam tabela.
--
-- A INTERFACE E O CONTRATO, O MOTOR E TROCAVEL. O Agent depende de
-- `buscar` -> candidatos {tipo,id,titulo,resumo} e `ler(tipo,id)` -> dossie. Por baixo,
-- hoje, e busca lexical (`mindagent_chat_search`, ja em producao). Trocar por hibrida
-- lexical+vetorial depois nao muda uma linha do Agent -- por isso a assinatura fala de
-- "necessidade", nao de "query".
--
-- POR QUE O CORTE POR CAMPO EXISTE. O dossie da Maslach tem 61.786 bytes crus; a media
-- dos 64 palestrantes e ~38 KB, concentrada em `principais_contribuicoes` (~12 KB) e
-- `relevancia_para_os_icps_do_mind` (~5,5 KB, ate 16 KB). Isso nao cabe num turno de
-- WhatsApp com orcamento de 20 s. O corte NAO remove campo: os 17 continuam presentes,
-- e o `…` avisa o modelo que ha mais, para ele nao afirmar completude sobre um texto
-- truncado. Com 1200 chars por campo, o mesmo dossie sai em 14.553 bytes.

create or replace function public.mind_txt_corta(p_texto text, p_n int)
returns text language sql immutable
as $function$
  select case
    when p_texto is null then null
    when length(p_texto) <= p_n then p_texto
    else left(p_texto, p_n) || '…'
  end;
$function$;

create or replace function public.mind_intelligence_buscar(
  p_necessidade text,
  p_limite      int default 6
) returns jsonb
language sql stable security definer
set search_path to 'public', 'summit_2026', 'ecossistema'
as $function$
  with lim as (select least(10, greatest(1, coalesce(p_limite, 6))) as n),
  busca as (
    select public.mindagent_chat_search(
             'mind-summit-2026',
             coalesce(nullif(btrim(p_necessidade), ''), 'programacao'),
             (select n from lim)) as s
  ),
  pessoas as (
    select jsonb_build_object('tipo','palestrante','id', e->>'id','titulo', e->>'name',
      'resumo', nullif(concat_ws(' · ', nullif(e->>'role',''), nullif(e->>'organization','')), '')) as c
    from busca, jsonb_array_elements(busca.s->'speakers') e
  ),
  sessoes as (
    select jsonb_build_object('tipo','sessao','id', e->>'id','titulo', e->>'title',
      'resumo', nullif(concat_ws(' · ', nullif(e->>'type',''),
                 nullif(e->>'starts_at_local','') || '–' || nullif(e->>'ends_at_local',''),
                 nullif(e->>'location','')), '')) as c
    from busca, jsonb_array_elements(busca.s->'sessions') e
  ),
  conhecimento as (
    select jsonb_build_object('tipo','conhecimento','id', k.id::text,'titulo', k.titulo,
      'resumo', nullif(concat_ws(' · ', nullif(k.tipo_conteudo,''), left(k.corpo, 160)), '')) as c
    from summit_2026.knowledge_documents k
    where k.ativo and 'concierge' = any(k.agents)
      and (k.valido_de is null or k.valido_de <= now())
      and (k.valido_ate is null or k.valido_ate > now())
      and to_tsvector('portuguese', coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo)
          @@ websearch_to_tsquery('portuguese', coalesce(p_necessidade, ''))
    order by ts_rank_cd(to_tsvector('portuguese', coalesce(k.tipo_conteudo,'') || ' ' || k.titulo || ' ' || k.corpo),
             websearch_to_tsquery('portuguese', coalesce(p_necessidade, ''))) desc, k.titulo
    limit (select n from lim)
  ),
  todos as (select c from pessoas union all select c from sessoes union all select c from conhecimento)
  select jsonb_build_object(
    'necessidade', p_necessidade,
    'candidatos', coalesce((select jsonb_agg(c order by c->>'tipo', c->>'titulo') from todos), '[]'::jsonb),
    'total', (select count(*) from todos),
    'como_usar', 'Cada candidato tem tipo e id. Para raciocinar sobre um deles, leia o objeto inteiro com ler_intelligence(tipo, id). Se nada aqui responder, reformule a necessidade e busque de novo — não complete com conhecimento próprio.'
  );
$function$;

create or replace function public.mind_intelligence_ler(p_tipo text, p_id text, p_corte int default 1200)
returns jsonb language sql stable security definer
set search_path to 'public', 'summit_2026', 'ecossistema'
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
          select jsonb_agg(jsonb_build_object('id', s.id,'titulo', s.titulo,'tipo', s.tipo,
            'dia', s.dia,'inicio', to_char(s.inicio at time zone e.fuso,'HH24:MI'),
            'fim', to_char(s.fim at time zone e.fuso,'HH24:MI'),
            'local', l.nome,'participacao', ss.papel) order by s.inicio)
          from summit_2026.session_speakers ss
          join summit_2026.sessions s on s.id = ss.sessao_id
          join summit_2026.events e on e.id = s.event_id and e.ativo
          left join summit_2026.locations l on l.id = s.espaco_id
          where ss.speaker_id = sp.id), '[]'::jsonb)))
      from ecossistema.palestrantes_especialistas sp
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where sp.id::text = p_id or sp.slug = p_id limit 1)
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
          select jsonb_agg(jsonb_build_object('id', sp.id,'nome', sp.nome,'cargo', sp.cargo_curto,
            'instituicao', sp.instituicao,'participacao', ss.papel) order by sp.nome)
          from summit_2026.session_speakers ss
          join ecossistema.palestrantes_especialistas sp on sp.id = ss.speaker_id
          where ss.sessao_id = s.id), '[]'::jsonb)))
      from summit_2026.sessions s
      join summit_2026.events e on e.id = s.event_id and e.ativo
      left join summit_2026.locations l on l.id = s.espaco_id
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where s.id::text = p_id limit 1)
    when 'conhecimento' then (
      select jsonb_strip_nulls(jsonb_build_object(
        'tipo','conhecimento','id', k.id,'titulo', k.titulo,'categoria', k.tipo_conteudo,
        'problema', k.problema,'resultado_desejado', k.resultado_desejado,
        'audiencia', k.audiencia,'cluster', k.cluster,
        'corpo', public.mind_txt_corta(k.corpo, n.v * 3),
        'autor', k.autor,'url', k.url))
      from summit_2026.knowledge_documents k
      cross join (select greatest(200, least(4000, coalesce(p_corte,1200))) as v) n
      where k.id::text = p_id and k.ativo and 'concierge' = any(k.agents)
        and (k.valido_de is null or k.valido_de <= now())
        and (k.valido_ate is null or k.valido_ate > now()) limit 1)
    else null end;
$function$;

comment on function public.mind_intelligence_buscar(text, int) is
  'Tool do Agent: encontra candidatos na Intelligence a partir de uma necessidade formulada pelo modelo. Le as casas canonicas (palestrantes, sessoes, knowledge_documents) pelo retrieval ja existente; nao cria fonte da verdade. Motor lexical hoje, trocavel sem mudar o contrato do Agent.';

comment on function public.mind_intelligence_ler(text, text, int) is
  'Tool do Agent: abre um objeto da Intelligence em profundidade a partir de tipo+id devolvidos por mind_intelligence_buscar. Le a casa canonica de cada tipo; nao duplica dado. Campos longos sao cortados com marca para caber num turno de WhatsApp. NULL quando o tipo e desconhecido ou o objeto nao existe/nao esta visivel.';

revoke all on function public.mind_txt_corta(text, int)                from public, anon, authenticated;
revoke all on function public.mind_intelligence_buscar(text, int)      from public, anon, authenticated;
revoke all on function public.mind_intelligence_ler(text, text, int)   from public, anon, authenticated;
grant execute on function public.mind_txt_corta(text, int)              to service_role;
grant execute on function public.mind_intelligence_buscar(text, int)    to service_role;
grant execute on function public.mind_intelligence_ler(text, text, int) to service_role;

drop function if exists public.mind_intelligence_ler(text, text);
