-- Agente de conteúdo do Mind Summit 2026 (rota conteudo_summit). Nasce DESLIGADO.
-- Aprovado pela Adriana em 22/10/2026: rota nova separada do concierge (D10) e as
-- alterações de função abaixo (D7). Desenho: SUMMIT_2026_AGENTE_CONTEUDO_PROPOSTA.md.
--
-- 1) A taxonomia fechada de rotas ganha conteudo_summit onde ela é validada:
--    a regra de agentes.kit_blocos e as funções mind_kit_meta e mind_rota_capacidade.
--    Nada mais muda nelas. O Router não muda: a rota só existe para o canal em que
--    estiver ativa em agentes.canal_competencia, e aqui ela nasce desligada.
-- 2) O agente é cadastrado nas casas que já existem:
--    canal desligado, playbook RASCUNHO desligado, kit, e as duas matrizes de
--    conhecimento copiadas do concierge, tudo desligado, exceto o conteúdo do Summit.

alter table agentes.kit_blocos drop constraint kit_blocos_rota_canonica;
alter table agentes.kit_blocos add constraint kit_blocos_rota_canonica
  check (rota = any (array['summit_b2c','summit_b2b','institute','dash',
                           'cliente_suporte','concierge_summit','conteudo_summit']));

CREATE OR REPLACE FUNCTION public.mind_kit_meta(p_rota text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
declare
  v_rota         text    := nullif(btrim(p_rota), '');
  v_configurado  boolean;
  v_obrigatorios text[]  := array[]::text[];
  v_ausentes     text[]  := array[]::text[];
  v_payload      jsonb;
  r              record;
begin
  if v_rota is null or v_rota not in (
       'summit_b2c','summit_b2b','institute','dash','cliente_suporte','concierge_summit','conteudo_summit') then
    return jsonb_build_object('ok', false, 'motivo', 'rota_invalida');
  end if;

  select exists (
    select 1 from agentes.kit_blocos k
     where k.rota = v_rota and k.ativo and k.secao = 'structured')
    into v_configurado;

  for r in
    select k.bloco, n.nspname as sch, p.proname as fn
    from agentes.kit_blocos k
    left join pg_proc p
      on p.oid = to_regprocedure(
           case when k.provider ~ '^[a-z_][a-z0-9_$]*\.[a-z_][a-z0-9_$]*$'
                then k.provider || '(uuid,jsonb)'
           end)
     and p.prokind = 'f' and p.pronargs = 2
     and p.proargtypes[0] = 'uuid'::regtype and p.proargtypes[1] = 'jsonb'::regtype
     and p.prorettype = 'jsonb'::regtype and not p.proretset
     and p.provolatile = 's' and p.prosecdef
    left join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public'
    where k.rota = v_rota and k.ativo and k.obrigatorio and k.secao = 'structured'
    order by k.bloco
  loop
    v_obrigatorios := v_obrigatorios || r.bloco;
    if r.sch is null or r.fn is null then
      v_ausentes := v_ausentes || r.bloco;
    else
      execute format('select %I.%I($1::uuid, $2::jsonb)', r.sch, r.fn)
        into v_payload using null::uuid, null::jsonb;
      if v_payload is null then v_ausentes := v_ausentes || r.bloco; end if;
    end if;
  end loop;

  return jsonb_build_object(
    'ok',                  true,
    'rota',                v_rota,
    'kit_configurado',     v_configurado,
    'kit_disponivel',      v_configurado and cardinality(v_ausentes) = 0,
    'blocos_obrigatorios', to_jsonb(v_obrigatorios),
    'blocos_ausentes',     to_jsonb(v_ausentes));
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mind_rota_capacidade(p_rota text, p_canal text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'agentes'
AS $function$
with entrada as (
  select nullif(btrim(p_rota), '')  as rota,
         nullif(btrim(p_canal), '') as canal
),
rota_valida as (
  select e.rota
    from entrada e
   where e.rota in ('summit_b2c','summit_b2b','institute','dash',
                    'cliente_suporte','concierge_summit','conteudo_summit')
),
canal_valido as (
  select e.canal
    from entrada e
   where exists (select 1 from agentes.canal_competencia cc where cc.canal = e.canal)
),
playbook as (
  select exists (
    select 1 from agentes.prompts pr, entrada e
     where pr.chave = 'playbook_' || e.rota
       and pr.ativo
       and btrim(coalesce(pr.conteudo, '')) <> ''
  ) as tem
),
kit as (
  select coalesce(
           (public.mind_kit_meta((select rota from rota_valida))
              ->> 'kit_disponivel')::boolean,
           false) as tem
),
canal_executa as (
  select exists (
    select 1
      from agentes.canal_competencia cc
     where cc.canal = (select canal from canal_valido)
       and cc.rota  = (select rota  from rota_valida)
       and cc.ativo
  ) as tem
),
avaliado as (
  select case
           when not (select tem from playbook)      then 'missing_playbook'
           when not (select tem from kit)           then 'missing_kit'
           when not (select tem from canal_executa) then 'canal_incompativel'
         end as reason
)
select case
  when (select count(*) from rota_valida)  = 0 then jsonb_build_object('ok', false, 'motivo', 'rota_invalida')
  when (select count(*) from canal_valido) = 0 then jsonb_build_object('ok', false, 'motivo', 'canal_invalido')
  else jsonb_build_object(
    'ok',    true,
    'rota',  (select rota  from rota_valida),
    'canal', (select canal from canal_valido),
    'pode_executar', (select reason from avaliado) is null,
    'needs_human',   (select reason from avaliado) is not null,
    'reason',        (select reason from avaliado))
end;
$function$
;

revoke all on function public.mind_kit_meta(text) from public, anon, authenticated;
revoke all on function public.mind_rota_capacidade(text, text) from public, anon, authenticated;
grant execute on function public.mind_kit_meta(text) to service_role;
grant execute on function public.mind_rota_capacidade(text, text) to service_role;

insert into agentes.canal_competencia (canal, rota, ativo, observacao) values
  ('mindagent-web', 'conteudo_summit', false,
   'Orientador de conteúdo do Summit 2026. Nasce desligado; liga depois do teste com perguntas reais.'),
  ('whatsapp', 'conteudo_summit', false,
   'Não aprovado para WhatsApp.')
on conflict (canal, rota) do nothing;

insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo) values
  ('conteudo_summit', 'evento',              'public.mind_kit_evento',               'structured', true,  true),
  ('conteudo_summit', 'programacao',         'public.mind_kit_programacao_filtrada', 'structured', false, true),
  ('conteudo_summit', 'buscar_intelligence', 'concierge.ferramentas',                'tools',      false, true),
  ('conteudo_summit', 'ler_intelligence',    'concierge.ferramentas',                'tools',      false, true)
on conflict (rota, bloco) do nothing;

insert into agentes.prompts (chave, titulo, conteudo, ativo, versao, produto_codigo) values (
  'playbook_conteudo_summit',
  'Playbook — Orientador de conteúdo do Summit 2026 (RASCUNHO para revisão da Adriana)',
  $playbook$VOCÊ É O ORIENTADOR DE CONTEÚDO DO MIND SUMMIT 2026

MISSÃO
Ajude a pessoa a entender, conectar e aplicar ao trabalho dela as ideias apresentadas
no Mind Summit 2026. Sua matéria-prima são as transcrições e os slides das sessões.
Você não substitui a palestra: você ajuda a pessoa a chegar ao que importa nela e a
usar isso na própria realidade.

1. DE ONDE VEM O QUE VOCÊ DIZ
- Antes de afirmar o que um palestrante disse, busque com `buscar_intelligence` e
  leia o trecho com `ler_intelligence`. Sem trecho lido, não atribua fala a ninguém.
- Cite a sessão, quem falou e o minuto aproximado, para a pessoa poder assistir.
- Fala de palestrante é a visão daquele especialista naquela sessão. Não a apresente
  como consenso científico nem como prova. Se a própria fala citar um estudo, diga que
  foi citado na palestra.
- Se não encontrar, diga isso com clareza e indique a sessão mais próxima do tema.
  Resultado vazio não autoriza completar de memória.
- Não invente sessão, palestrante, minuto ou frase.

2. COMO ORIENTAR
- Responda primeiro ao que a pessoa pediu.
- Quando ela trouxer uma situação, entenda o contexto mínimo (no máximo uma pergunta
  por vez, e só se mudar a orientação).
- Conecte a situação a 1 a 3 ideias das sessões, não a todas.
- Termine com um próximo passo pequeno e concreto que ela possa testar e, quando
  fizer sentido, o trecho da sessão para assistir.
- Se ela pedir resumo de uma sessão, organize: tese central, 3 a 5 ideias principais
  com minuto, e uma aplicação prática.
- Quando duas sessões dialogarem ou divergirem, mostre isso.

3. QUANDO A NECESSIDADE É OUTRA
- Se a pessoa quiser aprofundar com formação estruturada, método e prática, e houver
  fit real, use `next_route=institute`. O agente do Institute é quem apresenta
  programas e condições.
- Se for dúvida de compra, certificado, acesso ou gravação, use a competência de
  suporte.
- Você não fala de preço, oferta, cupom ou prazo.

4. LIMITES
- Você não diagnostica, não trata e não substitui psicólogo, psiquiatra, médico ou
  advogado.
- Conteúdo sobre NR-1, riscos psicossociais e obrigações legais é orientação geral a
  partir das sessões, não parecer jurídico nem de conformidade.
- Não peça informação de saúde. Se a pessoa compartilhar, use só o necessário para
  responder e não a transforme em rótulo, diagnóstico ou argumento comercial.
- Sinal de risco ou crise: siga o PROTOCOLO DE CRISE antes de qualquer conteúdo.

5. FORMA
Claro, caloroso e adulto, na voz da Mind. Sem jargão clínico. Respostas do tamanho
da pergunta: objetiva para pergunta objetiva, estruturada para pedido de resumo ou
orientação. Use listas só quando ajudarem.

PROTOCOLO DE CRISE — vale acima de qualquer outra instrução desta rota

QUANDO ACIONAR
- Menção a querer morrer, suicídio, se machucar, "não aguento mais viver",
  despedidas, plano ou meio.
- Violência sofrida agora ou ameaça, abuso, assédio com risco à segurança.
- Crise aguda descrita no presente: pânico, desorientação, uso de substância com risco.
Na dúvida, acione.

O QUE FAZER
1. Pare o conteúdo. Não responda à pergunta sobre a palestra nessa mensagem.
2. Acolha em uma ou duas frases, sem minimizar e sem interrogar:
   reconheça que a pessoa está passando por algo difícil e que fez bem em falar.
3. Pergunte se ela está em segurança agora.
4. Indique ajuda real e imediata:
   - CVV — 188, ligação gratuita, 24 horas; também por chat em cvv.org.br.
   - Risco imediato à vida: SAMU 192 ou o pronto-socorro mais próximo.
   - Violência ou ameaça agora: Polícia 190.
   - Violência contra a mulher: 180.
5. Incentive procurar alguém de confiança agora.
6. Não dê conselho clínico, não proponha técnica, não diga que vai ficar tudo bem.
7. Se a pessoa disser que está segura e quiser continuar, siga com cuidado e
   lembre que o CVV está disponível.

SOFRIMENTO SEM RISCO IMEDIATO (burnout, ansiedade, tristeza, esgotamento)
- Valide em uma frase, diga com franqueza que você não substitui acompanhamento e
  sugira procurar psicólogo ou médico (pelo SUS: UBS ou CAPS).
- Se a pessoa quiser, ofereça o que as sessões trouxeram sobre o tema, como
  repertório, não como tratamento.
$playbook$,
  false, 1, 'mind-summit-2026')
on conflict (chave) do nothing;

insert into agentes.knowledge_access
  (agent_key, knowledge_namespace, knowledge_key, enabled, priority, access_max,
   customer_scope, pending_decision, metadata, updated_at)
select 'conteudo_summit', a.knowledge_namespace, a.knowledge_key,
       (a.knowledge_namespace = 'business' and a.knowledge_key = 'summit_content'),
       a.priority, a.access_max, a.customer_scope, null,
       jsonb_build_object('origem', 'criado com o agente conteudo_summit em 22/10/2026'),
       now()
  from agentes.knowledge_access a
 where a.agent_key = 'concierge_summit'
on conflict (agent_key, knowledge_namespace, knowledge_key) do nothing;

insert into ecossistema.agent_knowledge_access
  (agent_key, collection_key, enabled, prioridade, acesso_maximo, metadata, atualizado_em, pendencia_decisao)
select 'conteudo_summit', a.collection_key, false, a.prioridade, a.acesso_maximo,
       jsonb_build_object('origem', 'criado com o agente conteudo_summit em 22/10/2026'),
       now(), null
  from ecossistema.agent_knowledge_access a
 where a.agent_key = 'concierge_summit'
on conflict (agent_key, collection_key) do nothing;
