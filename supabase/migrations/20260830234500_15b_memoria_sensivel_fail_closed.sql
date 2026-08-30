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
-- Mudança em relação à versão anterior: um único bloco novo, logo depois da
-- guarda que já existia. Todo o resto — derivação de tipo, chave, valor,
-- confiança, status, a substituição de identidade/cargo/empresa e o
-- tratamento de erro por item — é byte a byte o de antes.
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
      -- Persiste SÓ o item cujo rótulo for exatamente `none`. Tudo o mais
      -- para aqui: chave de bloqueio ativa, rótulo ausente, rótulo
      -- desconhecido, e o caso em que o modelo devolve a própria linha do
      -- enum (`none | saude_do_titular | ...`) em vez de escolher — o mesmo
      -- `like '%|%'` que a guarda de `category` acima já usa.
      --
      -- Chave de bloqueio INATIVA também não passa: ela não é `none` e não é
      -- bloqueio ativo, então cai em "desconhecido". Fail closed de novo.
      --
      -- O gate NÃO lê o texto, NÃO usa regex de conteúdo e NÃO infere
      -- sensibilidade a partir de `category` ou `scope`. Ele confere um
      -- rótulo declarado e obedece.
      --
      -- Vale para QUALQUER analisador, não só `analise_vendas_summit`: um
      -- gate que liberasse por nome de analisador deixaria o próximo passar
      -- sem contrato, e isso não seria fail closed. Analisador novo adota o
      -- contrato v2 antes de ser ativado.
      -- ---------------------------------------------------------------
      v_sens := lower(nullif(trim(coalesce(mem->>'sensitivity','')),''));

      if v_sens is null or v_sens like '%|%' then
        v_sem_rotulo := v_sem_rotulo + 1;
        continue;
      elsif v_sens <> 'none' then
        if exists (select 1 from intelligence.memoria_bloqueios b
                    where b.chave = v_sens and b.ativo) then
          v_bloqueadas := v_bloqueadas + 1;
        else
          v_sem_rotulo := v_sem_rotulo + 1;
        end if;
        continue;
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

      v_valor := jsonb_build_object('text', v_texto, 'scope', v_scope);
      v_num   := case v_conf when 'high' then 0.90 when 'medium' then 0.70 else 0.50 end;
      v_status := case when v_scope = 'stable' and v_conf = 'high' then 'ativa' else 'proposta' end;

      select * into v_exist from intelligence.participante_memoria pm
       where pm.participante_id = p_participante and pm.chave = v_chave
         and pm.status in ('ativa','proposta')
       order by (pm.status = 'ativa') desc, pm.atualizado_em desc nulls last
       limit 1;

      if found then
        if v_exist.valor->>'text' is not distinct from v_texto then
          update intelligence.participante_memoria
             set confianca           = greatest(coalesce(confianca, 0), v_num),
                 status              = case when status = 'ativa' or v_status = 'ativa'
                                            then 'ativa' else status end,
                 analise_conversa_id = coalesce(p_analise_id, analise_conversa_id),
                 atualizado_em       = now()
           where id = v_exist.id;
        elsif v_chave in ('identidade','cargo_atual','empresa_atual') then
          insert into intelligence.participante_memoria
            (participante_id, tipo, chave, valor, confianca, origem, status,
             evidencia_message_id, analise_conversa_id)
          values (p_participante, v_tipo, v_chave, v_valor, v_num, p_analisador, v_status,
                  null, p_analise_id)
          returning id into v_novo;
          update intelligence.participante_memoria
             set status = 'substituida', substituida_por = v_novo, atualizado_em = now()
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
  'Projeta dados.customer_memory do analisador em intelligence.participante_memoria. GATE DE SENSIBILIDADE FAIL CLOSED: so persiste item com sensitivity = none; chave ativa de intelligence.memoria_bloqueios, rotulo ausente, desconhecido, inativo ou enum ecoado nao persistem. Vale para qualquer analisador. Nao le o texto, nao usa regex de conteudo e nao infere sensibilidade por category/scope. Log so com contagem, nunca com o valor.';


-- ============================================================
-- 3. Silence D2 — `followup_exhausted` não tira da fila quem nunca recebeu
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
