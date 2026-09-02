-- ============================================================
-- Passo 15B — memória sensível: contrato no prompt, trava na escrita
--             + Silence D1 (contrato) e D2 (guard determinístico)
-- ------------------------------------------------------------
-- Decisões aprovadas na issue #42 (supervisão de 30/08/2026). Esta migration
-- implementa três coisas que andam juntas e não podem ser separadas:
--
--   1. `analise_vendas_summit` v2 passa a emitir `sensitivity` em cada item de
--      `customer_memory`: `none` OU exatamente uma chave ATIVA já existente em
--      `intelligence.memoria_bloqueios`. Nenhuma taxonomia, tabela ou coluna
--      nova — o vocabulário é o que já está no banco.
--
--   2. `public.analise_projetar_memoria` vira a trava determinística, FAIL
--      CLOSED: só persiste o item cujo `sensitivity` for exatamente `none`.
--      Ausente, desconhecido, inválido ou chave de bloqueio ativa → não
--      persiste. O prompt define o contrato; o writer é quem garante.
--
--   3. Silence: D1 no contrato (o prompt diz quando `stopped` vale) e D2 no
--      motor (`followup_exhausted` não pode tirar da fila quem tem
--      `followup_count = 0`).
--
-- POR QUE PROMPT E WRITER NA MESMA MIGRATION
--   O runtime do analisador chama a OpenAI com `json_object`, não com schema
--   strict — o modelo não é obrigado pelo transporte a emitir a chave nova.
--   Por isso o writer é fail closed. E por isso os dois têm de chegar juntos:
--   com o writer sozinho, o prompt v1 não emitiria `sensitivity` e a memória
--   pararia de ser escrita inteira; com o prompt sozinho, não haveria trava.
--
-- POR QUE A TRAVA NÃO OLHA O TEXTO
--   Uma varredura por palavra erraria nos dois sentidos neste domínio: num
--   evento de saúde mental, "é psicóloga clínica" é qualificação comercial e
--   "estou afastada por burnout" é dado do art. 11 — e as duas frases têm o
--   mesmo vocabulário. Quem sabe distinguir é quem leu a conversa, no momento
--   da extração. O writer não infere: ele confere um rótulo e obedece.
--
-- O QUE ESTA MIGRATION NÃO FAZ
--   Não apaga nem reescreve as 886 memórias já gravadas sob o contrato v1 —
--   elas continuam sem autorização de exposição ao Agent, e a proposta de
--   revalidação está no BACKLOG §16. Não liga o cron 13, não envia mensagem,
--   não escolhe canal de disparo (D3 segue gate). Não cria
--   `mind_lead_capturar`. Não toca no runtime da Lane B.
-- ============================================================


-- ============================================================
-- 1. `analise_vendas_summit` v2 — contrato de sensibilidade + contrato de
--    `stopped`. Três recortes cirúrgicos no prompt vigente; o restante do
--    output não muda.
--
--    `agentes.prompts` tem PK em `chave`: v2 é UPDATE da linha, não uma
--    segunda linha ativa. Isso importa porque `analise_prompt` faz
--    `where chave = ... and ativo` com `limit 1` — duas linhas ativas com a
--    mesma chave seriam um sorteio.
-- ============================================================

do $migration$
declare
  v_ancora_json constant text :=
'      "scope": "stable | opportunity | temporary",
      "confidence": "high | medium | low"';

  v_novo_json constant text :=
'      "scope": "stable | opportunity | temporary",
      "confidence": "high | medium | low",
      "sensitivity": "none | saude_do_titular | diagnostico_titular | medicacao_titular | afastamento_titular | saude_de_pessoa_citada | religiao | opiniao_politica | orientacao_sexual | origem_racial | filiacao_sindical"';

  v_ancora_stopped constant text :=
'stopped
Existe opt-out, encerramento explícito ou motivo real para interromper.';

  v_novo_stopped constant text :=
'stopped
Existe opt-out, encerramento explícito ou motivo real para interromper.

`stopped` é o fim da continuidade, não o fim da mensagem. Só use quando a
continuidade REALMENTE deve parar: opt-out, recusa inequívoca, impossibilidade
real, ou compra. Conversa que terminou com assunto em aberto — pergunta sem
resposta, checkout não concluído, decisão pendente, compromisso de retorno,
ou qualquer retomada legítima — NÃO é `stopped`. Ela é `silence`,
`commitment_pending` ou `followup_due`, conforme os critérios acima.

"A conversa acabou" nunca é, sozinho, motivo para `stopped`.';

  v_ancora_regras constant text := 'REGRAS ABSOLUTAS';

  v_secao_sens constant text :=
'SENSIBILIDADE (LGPD) — OBRIGATÓRIO EM TODO ITEM DE customer_memory

Todo item de `customer_memory` precisa trazer `sensitivity`. Sem ele, o item é
descartado na gravação — não há valor padrão e não há inferência.

Use exatamente um destes valores:

none
O item não revela dado pessoal sensível do titular nem de terceiro
identificável. É o caso da esmagadora maioria: cargo, empresa, interesse
comercial, objeção, logística, orçamento, papel na decisão.

saude_do_titular
A pessoa revelou algo sobre a PRÓPRIA saúde física ou mental.

diagnostico_titular
Diagnóstico, laudo ou condição clínica do próprio titular.

medicacao_titular
Medicação ou tratamento em uso pelo próprio titular.

afastamento_titular
Afastamento, licença médica ou readaptação do próprio titular.

saude_de_pessoa_citada
Saúde de alguém identificável que não é o titular — filho, cônjuge, um
colaborador nomeado.

religiao
Religião ou convicção religiosa do titular.

opiniao_politica
Opinião ou filiação política do titular.

orientacao_sexual
Orientação sexual do titular.

origem_racial
Origem racial ou étnica do titular.

filiacao_sindical
Filiação sindical do titular.

COMO DECIDIR — o que separa os casos é O SUJEITO E O QUE A FRASE AFIRMA, nunca
as palavras que aparecem nela. Este é um evento de saúde mental: o vocabulário
clínico é o vocabulário da profissão do público.

- "é psicóloga clínica", "estudante de Psicologia", "trabalha com saúde mental
  corporativa", "quer conteúdo sobre burnout" → `none`. São profissão e
  interesse, não dado de saúde de ninguém.
- "está afastada por burnout", "toma medicação para ansiedade", "foi
  diagnosticada com TDAH" → a chave correspondente. É a própria pessoa
  falando da própria condição.
- "o filho dela tem autismo" → `saude_de_pessoa_citada`.

Na dúvida entre `none` e uma chave sensível, escolha a chave sensível: o item
não será gravado, e perder uma memória comercial é melhor que persistir dado do
art. 11.

';
  v_antes text;
  v_depois text;
begin
  select conteudo into v_antes from agentes.prompts where chave = 'analise_vendas_summit';
  if v_antes is null then
    raise exception 'prompt analise_vendas_summit nao existe';
  end if;

  -- Cada âncora precisa existir. Um replace que não casa seria um no-op
  -- silencioso: o writer entraria fail closed contra um prompt sem contrato,
  -- e a memória pararia de ser gravada sem ninguém perceber.
  if position(v_ancora_json in v_antes) = 0 then
    raise exception 'ancora do bloco customer_memory nao encontrada no prompt';
  end if;
  if position(v_ancora_stopped in v_antes) = 0 then
    raise exception 'ancora da definicao de stopped nao encontrada no prompt';
  end if;
  if position(v_ancora_regras in v_antes) = 0 then
    raise exception 'ancora REGRAS ABSOLUTAS nao encontrada no prompt';
  end if;

  v_depois := replace(v_antes, v_ancora_json,    v_novo_json);
  v_depois := replace(v_depois, v_ancora_stopped, v_novo_stopped);
  v_depois := replace(v_depois, v_ancora_regras,  v_secao_sens || v_ancora_regras);

  update agentes.prompts
     set conteudo      = v_depois,
         versao        = 2,
         ativo         = true,
         atualizado_em = now()
   where chave = 'analise_vendas_summit';

  raise notice 'analise_vendas_summit v2: % -> % chars', length(v_antes), length(v_depois);
end
$migration$;


-- ============================================================
-- 2. `analise_projetar_memoria` — a trava determinística.
--
-- Três mudanças em relação à versão anterior, e nada mais:
--
--   a) GATE DE SENSIBILIDADE, restrito ao contrato aprovado
--      (`p_analisador = 'analise_vendas_summit'`). É o único analisador com
--      análises vivas hoje; os outros prompts estão inativos. Quando
--      `analise_concierge` ganhar contrato v2, ele entra aqui explicitamente,
--      nominalmente, naquele passo — sem registry e sem regra global calada.
--
--   b) MARCADOR DE VALIDAÇÃO dentro do `valor` que já existe. Item aprovado
--      sob o contrato v2 grava `sensitivity: 'none'` junto de `text`/`scope`.
--      É o que permite ao coletor separar o que foi validado do legado v1 sem
--      coluna nova, sem status novo e sem apagar as 886 linhas antigas.
--      O caminho "mesmo texto já existe" TAMBÉM marca: é assim que uma linha
--      antiga é revalidada em vez de duplicada.
--      Analisador fora do contrato não marca nada — o que ele grava continua
--      invisível para o coletor, que é o resultado seguro.
--
--   c) ORDEM DA SUBSTITUIÇÃO corrigida (bug, não decisão nova).
--
-- Todo o resto — derivação de tipo, chave, confiança, status e o tratamento de
-- erro por item — é byte a byte o de antes.
-- ============================================================

create or replace function public.analise_projetar_memoria(
  p_participante uuid,
  p_analisador text,
  p_memorias jsonb,
  p_analise_id uuid default null::uuid
) returns integer
language plpgsql
security definer
set search_path to 'public', 'intelligence'
as $function$
declare
  mem jsonb; v_cat text; v_texto text; v_scope text; v_conf text;
  v_tipo text; v_chave text; v_valor jsonb; v_num numeric; v_status text;
  v_sens text;
  -- O contrato v2 vale, hoje, para este analisador. Analisador novo entra aqui
  -- por nome, no passo em que ganhar prompt v2 — nunca por omissão.
  v_sob_contrato constant boolean := (p_analisador = 'analise_vendas_summit');
  v_exist intelligence.participante_memoria%rowtype; v_novo uuid; v_n int := 0;
  v_bloqueadas int := 0; v_sem_rotulo int := 0;
begin
  if p_participante is null or jsonb_typeof(p_memorias) <> 'array' then return 0; end if;

  for mem in select * from jsonb_array_elements(p_memorias)
  loop
    begin
      v_cat   := lower(nullif(trim(coalesce(mem->>'category','')),''));
      v_texto := nullif(trim(coalesce(mem->>'value','')),'');
      v_scope := lower(coalesce(nullif(trim(coalesce(mem->>'scope','')),''), 'opportunity'));
      v_conf  := lower(coalesce(nullif(trim(coalesce(mem->>'confidence','')),''), 'low'));

      continue when v_texto is null or v_cat is null or v_cat like '%|%';

      -- ---------------------------------------------------------------
      -- GATE DE SENSIBILIDADE — FAIL CLOSED.
      --
      -- Só passa o item cujo rótulo for exatamente `none`. Ausente, vazio,
      -- desconhecido, chave de bloqueio (ativa ou inativa) e o caso em que o
      -- modelo devolve a própria linha do enum: nenhum persiste.
      --
      -- A consulta a `memoria_bloqueios` NÃO decide nada — a decisão é
      -- `<> 'none'`. Ela só separa "barrado por política" de "rótulo inválido"
      -- na contagem do log, que é o que torna o problema diagnosticável.
      --
      -- O gate não lê o texto, não usa regex de conteúdo e não infere
      -- sensibilidade a partir de `category` ou `scope`.
      -- ---------------------------------------------------------------
      if v_sob_contrato then
        v_sens := lower(nullif(trim(coalesce(mem->>'sensitivity','')),''));

        if v_sens is distinct from 'none' then
          if v_sens is not null
             and exists (select 1 from intelligence.memoria_bloqueios b
                          where b.chave = v_sens and b.ativo)
            then v_bloqueadas := v_bloqueadas + 1;
            else v_sem_rotulo := v_sem_rotulo + 1;
          end if;
          continue;
        end if;
      end if;

      v_tipo := case v_cat
        when 'identity' then 'identidade'      when 'role' then 'cargo'
        when 'company' then 'empresa'          when 'goal' then 'objetivo'
        when 'interest' then 'interesse'       when 'preference' then 'preferencia'
        when 'constraint' then 'restricao'     when 'commercial_preference' then 'preferencia_comercial'
        when 'stakeholder' then 'stakeholder'  when 'delegation' then 'delegacao'
        when 'sponsorship' then 'patrocinio'   when 'logistics' then 'logistica'
        else 'outro' end;

      v_chave := case v_tipo
        when 'identidade' then 'identidade'
        when 'cargo'      then 'cargo_atual'
        when 'empresa'    then 'empresa_atual'
        else v_tipo || ':' || public.mind_slug(v_texto) end;

      -- MARCADOR. Só quem passou pelo contrato v2 é marcado.
      v_valor := jsonb_build_object('text', v_texto, 'scope', v_scope)
                 || case when v_sob_contrato
                         then jsonb_build_object('sensitivity', 'none')
                         else '{}'::jsonb end;

      v_num   := case v_conf when 'high' then 0.90 when 'medium' then 0.70 else 0.50 end;
      v_status := case when v_scope = 'stable' and v_conf = 'high' then 'ativa' else 'proposta' end;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.participante_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          -- MESMO TEXTO = REVALIDAÇÃO, não duplicata. A linha que já existia
          -- ganha o marcador sem que `text` ou `scope` mudem. É por aqui que
          -- uma memória v1 se torna visível ao coletor: ela não é reescrita,
          -- só passa a carregar a prova de que foi avaliada sob o contrato v2.
          update intelligence.participante_memoria
             set confianca           = greatest(coalesce(confianca, 0), v_num),
                 status              = case when status = 'ativa' or v_status = 'ativa'
                                            then 'ativa' else status end,
                 valor               = case when v_sob_contrato
                                            then valor || jsonb_build_object('sensitivity', 'none')
                                            else valor end,
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em       = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual') then
          -- ORDEM CORRIGIDA (30/08/2026). Rebaixa a antiga ANTES de inserir a
          -- nova. O índice parcial `UNIQUE (participante_id, chave) WHERE
          -- status = 'ativa'` recusava a segunda `ativa`, o insert levantava
          -- `unique_violation`, o EXCEPTION deste bloco engolia, e a troca de
          -- cargo/empresa/identidade sumia sem erro visível. A semântica já
          -- estava no código; era só a ordem.
          --
          -- `substituida_por` só pode ser preenchido depois do insert, então
          -- são três passos. Se o insert falhar, o EXCEPTION deste bloco
          -- reverte também o rebaixamento: em PL/pgSQL um bloco com EXCEPTION
          -- é uma subtransação.
          update intelligence.participante_memoria
             set status = 'substituida', atualizado_em = now()
           where id = v_exist.id;

          insert into intelligence.participante_memoria
            (participante_id, tipo, chave, valor, confianca, origem, status,
             evidencia_message_id, analise_conversa_id)
          values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                  null, p_analise_id)
          returning id into v_novo;

          update intelligence.participante_memoria
             set substituida_por = v_novo
           where id = v_exist.id;

          v_n := v_n + 1;
        end if;
      else
        insert into intelligence.participante_memoria
          (participante_id, tipo, chave, valor, confianca, origem, status,
           evidencia_message_id, analise_conversa_id)
        values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                null, p_analise_id);
        v_n := v_n + 1;
      end if;
    exception when others then
      raise warning 'projecao_memoria falhou p/ item: %', sqlerrm;
    end;
  end loop;

  -- Contagem, nunca conteúdo: o texto de um item bloqueado não vai para o log.
  if v_bloqueadas > 0 or v_sem_rotulo > 0 then
    raise notice 'projecao_memoria (%): % gravadas, % bloqueadas por sensibilidade, % sem rotulo valido',
      p_analisador, v_n, v_bloqueadas, v_sem_rotulo;
  end if;

  return v_n;
end $function$;

revoke all on function public.analise_projetar_memoria(uuid, text, jsonb, uuid)
  from public, anon, authenticated;
grant execute on function public.analise_projetar_memoria(uuid, text, jsonb, uuid) to service_role;

comment on function public.analise_projetar_memoria(uuid, text, jsonb, uuid) is
  'Projeta dados.customer_memory em intelligence.participante_memoria. GATE DE SENSIBILIDADE FAIL CLOSED para p_analisador = analise_vendas_summit (unico contrato v2 hoje): so persiste item com sensitivity = none; ausente, desconhecido ou chave de bloqueio nao persistem. Item aprovado grava o marcador valor.sensitivity = none, inclusive no caminho de mesmo texto — e o que o coletor usa para separar validado de legado v1. Nao le o texto, nao usa regex de conteudo e nao infere por category/scope. Substituicao de identidade/cargo/empresa rebaixa a antiga antes de inserir a nova (a ordem inversa perdia o item no indice parcial).';


-- ============================================================
-- 3. `mindagent_chat_save_interests` — o SEGUNDO writer vivo, agora no mesmo
--    gate.
--
-- Coordenação cross-lane C→D (issue #42): esta RPC é o outro caminho que
-- escreve memória, e até aqui ela não passava por gate nenhum. Ela grava todo
-- interesse aceito em `engagement.session_interests` — inclusive em sessão sem
-- participante identificado — e, quando o item vem confirmado com confiança
-- alta e há pessoa, promove para `intelligence.participante_memoria` e
-- `intelligence.participante_contexto`.
--
-- `session_interests` É PERSISTÊNCIA. Por isso o gate roda ANTES dela, não só
-- antes da promoção: proteger apenas o segundo salto deixaria o dado sensível
-- gravado no primeiro.
--
-- CONTRATO, o mesmo da §2, sem segunda taxonomia: cada item de `p_interests`
-- traz `sensitivity` — `none` ou uma chave de `intelligence.memoria_bloqueios`.
-- Só `none` grava. Ausente, desconhecido ou chave bloqueada: nada é gravado
-- para aquele item. A decisão é `<> 'none'`, então nem é preciso consultar a
-- tabela de bloqueios aqui — o vocabulário importa para quem EMITE o rótulo,
-- não para quem o confere.
--
-- A ASSINATURA DA RPC NÃO MUDA. `sensitivity` viaja dentro de `p_interests`,
-- que já é jsonb. A Lane C é dona da Edge `mindagent-chat` e acrescenta o campo
-- ao structured output; o gate no banco é desta lane. Enquanto o campo não vier,
-- o writer fica fail closed — que é o estado seguro, não uma regressão
-- silenciosa: `blocked` no retorno diz exatamente quantos itens caíram.
--
-- MARCADOR: o item aprovado grava `sensitivity: 'none'` no `valor` da memória e
-- no item de perfil, igual à §2 — é o que o coletor exige para expor a linha.
--
-- O retorno ganha UMA chave aditiva (`blocked`). Nenhuma existente muda.
-- ============================================================

create or replace function public.mindagent_chat_save_interests(
  p_auth_user_id uuid,
  p_session_id uuid,
  p_token_hash text,
  p_interests jsonb,
  p_evidence_message_id uuid default null::uuid
) returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'engagement', 'intelligence', 'summit', 'comum', 'concierge'
as $function$
declare
  v_item jsonb;
  v_saved integer := 0;
  v_promoted integer := 0;
  v_session_skipped integer := 0;
  v_permanent_skipped integer := 0;
  v_blocked integer := 0;
  v_key text;
  v_label text;
  v_confidence numeric;
  v_confirmed boolean;
  v_sens text;
  v_participant_id uuid;
  v_profile_item jsonb;
  v_interest_exists boolean;
  v_interest_count integer;
begin
  select s.participante_id
    into v_participant_id
  from engagement.agent_sessions s
  where s.id = p_session_id
    and s.auth_user_id = p_auth_user_id
    and s.token_hash = p_token_hash
    and s.expira_em > now();

  if not found then
    raise exception using errcode = '28000', message = 'invalid_chat_session';
  end if;

  if p_interests is null or jsonb_typeof(p_interests) <> 'array' then
    return jsonb_build_object(
      'saved', 0, 'promoted', 0, 'session_skipped', 0, 'permanent_skipped', 0, 'blocked', 0);
  end if;

  if jsonb_array_length(p_interests) > 5 then
    raise exception using errcode = '22023', message = 'too_many_interests';
  end if;

  for v_item in select value from jsonb_array_elements(p_interests)
  loop
    v_key := left(lower(regexp_replace(coalesce(v_item->>'key', ''), '[^a-z0-9_\-]+', '_', 'g')), 80);
    v_label := left(btrim(coalesce(v_item->>'label', '')), 120);
    v_confidence := least(1, greatest(0, coalesce((v_item->>'confidence')::numeric, 0.7)));
    v_confirmed := lower(coalesce(v_item->>'confirmed', 'false')) in ('true', '1', 'yes');

    -- GATE DE SENSIBILIDADE — FAIL CLOSED, ANTES DE QUALQUER GRAVAÇÃO,
    -- inclusive antes de `session_interests`.
    v_sens := lower(nullif(trim(coalesce(v_item->>'sensitivity', '')), ''));
    if v_sens is distinct from 'none' then
      v_blocked := v_blocked + 1;
      continue;
    end if;

    if length(v_key) >= 2 and length(v_label) >= 2 and v_confidence >= 0.70 then
      select exists (
        select 1
        from engagement.session_interests si
        where si.agent_session_id = p_session_id
          and si.chave = v_key
      ) into v_interest_exists;

      select count(*)
        into v_interest_count
      from engagement.session_interests si
      where si.agent_session_id = p_session_id;

      if v_interest_exists or v_interest_count < 12 then
        insert into engagement.session_interests (
          agent_session_id, chave, rotulo, confianca,
          evidencia_message_id, ocorrencias, primeira_em, ultima_em
        ) values (
          p_session_id, v_key, v_label, v_confidence,
          p_evidence_message_id, 1, now(), now()
        )
        on conflict (agent_session_id, chave) do update
          set rotulo = excluded.rotulo,
              confianca = greatest(engagement.session_interests.confianca, excluded.confianca),
              evidencia_message_id = coalesce(excluded.evidencia_message_id, engagement.session_interests.evidencia_message_id),
              ocorrencias = engagement.session_interests.ocorrencias + 1,
              ultima_em = now();

        v_saved := v_saved + 1;
      else
        v_session_skipped := v_session_skipped + 1;
      end if;

      if v_confirmed and v_confidence >= 0.85 and v_participant_id is not null then
        perform pg_advisory_xact_lock(hashtextextended('mindagent-interest:' || v_participant_id::text, 0));

        select exists (
          select 1
          from intelligence.participante_memoria pm
          where pm.participante_id = v_participant_id
            and pm.tipo = 'interesse'
            and pm.chave = v_key
            and pm.status = 'ativa'
        ) into v_interest_exists;

        select count(*)
          into v_interest_count
        from intelligence.participante_memoria pm
        where pm.participante_id = v_participant_id
          and pm.tipo = 'interesse'
          and pm.status = 'ativa';

        if v_interest_exists or v_interest_count < 8 then
          -- MARCADOR no item de perfil, igual ao da memória.
          v_profile_item := jsonb_build_object(
            'key', v_key,
            'label', v_label,
            'source', 'confirmado_pelo_usuario',
            'confirmed', true,
            'confidence', v_confidence,
            'sensitivity', 'none'
          );

          insert into intelligence.participante_memoria (
            participante_id, tipo, chave, valor, confianca, origem,
            evidencia_message_id, status, importancia, criado_em, atualizado_em
          ) values (
            v_participant_id, 'interesse', v_key,
            -- MARCADOR: sem ele o coletor não expõe a linha.
            jsonb_build_object('label', v_label, 'confirmed', true, 'sensitivity', 'none'),
            v_confidence, 'confirmado_pelo_usuario',
            p_evidence_message_id, 'ativa', v_confidence, now(), now()
          )
          on conflict (participante_id, chave) where status = 'ativa' do update
            set tipo = 'interesse',
                valor = excluded.valor,
                confianca = greatest(intelligence.participante_memoria.confianca, excluded.confianca),
                origem = 'confirmado_pelo_usuario',
                evidencia_message_id = coalesce(excluded.evidencia_message_id, intelligence.participante_memoria.evidencia_message_id),
                importancia = greatest(coalesce(intelligence.participante_memoria.importancia, 0), excluded.importancia),
                atualizado_em = now();

          insert into intelligence.participante_contexto as pc (
            participante_id, temas_relevantes, versao, atualizado_em
          ) values (
            v_participant_id, jsonb_build_array(v_profile_item), 1, now()
          )
          on conflict (participante_id) do update
            set temas_relevantes =
              coalesce(
                (
                  select jsonb_agg(existing_item)
                  from jsonb_array_elements(
                    case
                      when jsonb_typeof(pc.temas_relevantes) = 'array' then pc.temas_relevantes
                      else '[]'::jsonb
                    end
                  ) as existing(existing_item)
                  where existing_item->>'key' <> v_key
                ),
                '[]'::jsonb
              ) || jsonb_build_array(v_profile_item),
              versao = pc.versao + 1,
              atualizado_em = now();

          v_promoted := v_promoted + 1;
        else
          v_permanent_skipped := v_permanent_skipped + 1;
        end if;
      end if;
    end if;
  end loop;

  return jsonb_build_object(
    'saved', v_saved,
    'promoted', v_promoted,
    'session_skipped', v_session_skipped,
    'permanent_skipped', v_permanent_skipped,
    'blocked', v_blocked
  );
exception
  when invalid_text_representation then
    raise exception using errcode = '22023', message = 'invalid_interest_confidence';
end;
$function$;

comment on function public.mindagent_chat_save_interests(uuid, uuid, text, jsonb, uuid) is
  'Salva interesses da superficie web. GATE DE SENSIBILIDADE FAIL CLOSED antes de QUALQUER gravacao, inclusive engagement.session_interests: so grava item com sensitivity = none dentro de p_interests; ausente, desconhecido ou chave de bloqueio nao gravam nada. Assinatura preservada — o campo viaja no jsonb. Item aprovado grava o marcador sensitivity = none no valor da memoria e no item de perfil. Retorno ganha a chave aditiva blocked; as demais nao mudam.';


-- ============================================================
-- 4. Silence D2 — `followup_exhausted` não tira da fila quem nunca recebeu
--    follow-up.
--
-- Uma condição a mais no ramo DORMANT. Todo o resto da função é idêntico:
-- mesma precedência, mesma matriz, mesmo piso, mesmas chaves de saída.
--
-- Com `followup_count = 0` nada foi esgotado — `DORMANT por
-- followup_exhausted` seria a oportunidade saindo da fila para sempre sem que
-- uma única retomada tivesse acontecido. Com a guarda, o turno segue o
-- caminho normal e vira `silence` (com ou sem motivo legítimo de recontato),
-- que continua sendo uma decisão conservadora: `silence` não envia nada.
--
-- Compra e opt-out são testados ANTES deste ramo e continuam intocados: quem
-- comprou ou pediu descadastro nunca chega aqui.
--
-- O outro ponto que emite `followup_exhausted` — o fim da lista
-- `apos_followup_min` — é inalcançável com `v_fc = 0`, porque aquele ramo só
-- roda no `else` de `if v_fc = 0`. Não precisa de guarda e não ganhou uma.
-- ============================================================

create or replace function public.silence_calcular_next_review(
  p_conversa_id uuid,
  p_dados jsonb,
  p_followup_count integer default 0,
  p_last_followup_at timestamp with time zone default null::timestamp with time zone,
  p_action text default null::text,
  p_piso timestamp with time zone default null::timestamp with time zone
) returns jsonb
language plpgsql
stable
as $function$
declare
  v_cfg      jsonb;
  v_acao     text := upper(coalesce(p_action,''));
  v_compra   text;
  v_declarou boolean;
  v_optout   text;
  v_status   text := lower(coalesce(p_dados->>'continuation_status',''));
  v_ancora   timestamptz;
  v_due      timestamptz;
  v_openloop text;
  v_handoff  text := lower(coalesce(p_dados#>>'{ownership,handoff_status}',''));
  v_chave    text;
  v_lista    jsonb;
  v_min      integer;
  v_next     timestamptz;
  v_policy   text;
  v_fc       integer := greatest(coalesce(p_followup_count,0), 0);
  v_adiado   boolean := false;
begin
  select c.valor into v_cfg from intelligence.config c where c.chave = 'silence_timing_v1';
  if v_cfg is null then
    return jsonb_build_object('erro','config silence_timing_v1 ausente');
  end if;

  v_ancora := case when v_fc > 0
                   then coalesce(p_last_followup_at, public.silence_ultimo_evento(p_conversa_id))
                   else public.silence_ultimo_evento(p_conversa_id) end;

  v_compra := public.silence_compra_summit_2026(p_conversa_id);
  v_declarou := lower(coalesce(p_dados#>>'{transaction,purchase_status}','')) = 'purchased'
             or lower(coalesce(p_dados->>'purchase_status','')) = 'purchased';
  v_optout := public.summit_motivo_exclusao(p_conversa_id);
  v_openloop := nullif(btrim(coalesce(p_dados->>'open_loop','')), '');
  if lower(coalesce(v_openloop,'')) in ('none','null','n/a','nenhum') then v_openloop := null; end if;

  -- ---------------- PRECEDENCIA (secao 7 do playbook) ----------------
  if v_compra = 'purchased' or v_declarou then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','none',
      'continuation_status','stopped',
      'reason_code', case when v_compra = 'purchased' then 'purchase_confirmed_crm'
                          else 'purchase_declared' end,
      'prova_de_compra', v_compra = 'purchased',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_optout is not null then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','none',
      'continuation_status','stopped','reason_code','opt_out','motivo_opt_out', v_optout,
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_acao = 'STOP' or (v_acao = '' and v_status = 'stopped') then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','none',
      'continuation_status','stopped','reason_code', coalesce(nullif(p_dados->>'reason_code',''),'stopped'),
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  -- D2: `and v_fc > 0`. Sem retomada feita, nada foi esgotado.
  if (v_acao = 'DORMANT' or (v_acao = '' and v_status = 'dormant')) and v_fc > 0 then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','dormant','reason_code','followup_exhausted',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_acao = 'ESCALATE' and (v_handoff in ('done','accepted','assigned','in_progress')
                              or nullif(btrim(coalesce(p_dados#>>'{ownership,human_owner}','')),'') is not null) then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','scheduled_pause','reason_code','handoff_owned',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  -- 3. sem open loop real: silencio nao autoriza follow-up
  if v_openloop is null then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','silence','reason_code','no_legitimate_recontact_reason',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  if v_ancora is null then
    return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
      'continuation_status','silence','reason_code','sem_ancora_temporal',
      'timing_key', null, 'anchor_at', null, 'purchase_status', v_compra);
  end if;

  -- minutos da matriz (sempre calculados: viram o passo do piso quando preciso)
  v_chave := public.silence_chave_timing(p_dados, v_fc > 0);
  if v_fc = 0 then
    v_min := (v_cfg#>>array['primeira_reavaliacao_min', v_chave])::integer;
  else
    v_lista := v_cfg#>array['apos_followup_min', v_chave];
    if v_lista is null or v_fc > jsonb_array_length(v_lista) then
      return jsonb_build_object('next_review_at', null, 'next_review_policy','event_trigger_only',
        'continuation_status','dormant','reason_code','followup_exhausted',
        'timing_key', v_chave, 'anchor_at', v_ancora, 'purchase_status', v_compra);
    end if;
    v_min := (v_lista->>(v_fc - 1))::integer;
  end if;

  -- 2. compromisso explicito prevalece sobre o timer (se ainda nao venceu)
  v_due := public.silence_ts(p_dados#>>'{commitment,due}');
  if v_due is not null and v_due > v_ancora and (p_piso is null or v_due > p_piso) then
    return jsonb_build_object('next_review_at', v_due, 'next_review_policy','commitment_due',
      'continuation_status','commitment_pending','reason_code','commitment_due',
      'timing_key', null, 'anchor_at', v_ancora, 'purchase_status', v_compra);
  end if;

  -- 4. matriz deterministica
  v_next   := v_ancora + make_interval(mins => v_min);
  v_policy := 'timing_matrix';

  -- PISO: numa reavaliacao o proximo passo nunca fica no passado.
  if p_piso is not null and v_next <= p_piso then
    v_next   := p_piso + make_interval(mins => v_min);
    v_adiado := true;
  end if;

  return jsonb_build_object(
    'next_review_at',      v_next,
    'next_review_policy',  v_policy,
    'continuation_status', case when v_fc = 0 then 'silence' else 'followup_due' end,
    'reason_code',         coalesce(nullif(p_dados->>'reason_code',''), 'timing_matrix'),
    'timing_key',          v_chave,
    'timing_minutos',      v_min,
    'anchor_at',           v_ancora,
    'ancorado_no_piso',    v_adiado,
    'compromisso_vencido', (v_due is not null and (v_due <= v_ancora or (p_piso is not null and v_due <= p_piso))),
    'purchase_status',     v_compra);
end $function$;

comment on function public.silence_calcular_next_review(uuid, jsonb, integer, timestamptz, text, timestamptz) is
  'Calcula a proxima revisao de continuidade. Precedencia: compra > opt-out > stopped > dormant > escalate > sem open loop > matriz. D2 (30/08/2026): o ramo dormant/followup_exhausted exige followup_count > 0 — sem retomada feita nada foi esgotado, e a oportunidade segue para silence em vez de sair da fila. Compra e opt-out sao testados antes e nao mudam. Nao envia nada e nao decide canal.';
