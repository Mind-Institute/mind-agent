-- ============================================================
-- Passo 12B.2 — o Capability Gate passa a ler mind_kit_meta
-- ------------------------------------------------------------
-- MENOR MUDANÇA POSSÍVEL. Só a célula `kit` de
-- public.mind_rota_capacidade muda. Tudo o mais é byte a byte o que já estava
-- em produção: assinatura (text, text), volatilidade STABLE, SECURITY DEFINER,
-- search_path = public, agentes, as seis rotas canônicas, os dois canais vivos,
-- a leitura de playbook em agentes.prompts, os reasons e a precedência
-- fechada missing_playbook > missing_kit > canal_incompativel.
--
-- O QUE SAI
--   Uma lista fixa no corpo do Gate — ('summit_b2c','concierge_summit') — que
--   era um retrato manual do que o runtime alcançava em agosto/2026 e que
--   precisava ser reeditada toda vez que a realidade mudasse.
--
-- O QUE ENTRA
--   `public.mind_kit_meta(rota) ->> 'kit_disponivel'`, que é a ÚNICA verdade de
--   completude do Kit desde o Passo 12B.1C. O Gate deixa de ter uma segunda
--   lógica de completude e passa a ler a primeira. Nada de kit_blocos, provider,
--   evento, oferta, regra, inclusão ou preço aparece aqui: o Gate continua sem
--   conhecer fonte alguma.
--
-- EFEITO REAL EM PRODUÇÃO, MEDIDO ANTES DA MUDANÇA
--   summit_b2c        kit true  -> true   sem efeito
--   summit_b2b        kit false -> TRUE   deixa de ser missing_kit
--   institute         kit false -> false  sem efeito (missing_playbook domina)
--   dash              kit false -> false  sem efeito (missing_playbook domina)
--   cliente_suporte   kit false -> false  sem efeito
--   concierge_summit  kit true  -> FALSE  sem efeito HOJE (missing_playbook domina)
--
--   summit_b2b é a mudança pretendida: a §12 do PROJECT_STATE condiciona o
--   missing_kit dessa rota a "a Intelligence B2B existir no banco mas não
--   chegar de forma canônica ao runtime". Com o Kit Loader entregando os cinco
--   blocos obrigatórios (evento, inclusoes, ofertas, precos_por_volume,
--   regras_comerciais) com blocos_ausentes vazio, a condição deixou de valer.
--
--   concierge_summit NÃO tem linha em agentes.kit_blocos, então mind_kit_meta
--   devolve kit_configurado=false e kit_disponivel=false. Hoje isso é inócuo,
--   porque a rota não tem playbook ativo e a precedência entrega
--   missing_playbook antes de olhar o kit. No dia em que o playbook do
--   concierge for escrito, a rota passa a responder missing_kit até que seus
--   blocos sejam registrados no registry. Isso é registro de conteúdo, não é
--   mudança de Gate, e fica fora deste passo.
-- ============================================================

create or replace function public.mind_rota_capacidade(p_rota text, p_canal text)
returns jsonb
language sql
stable
security definer
set search_path = public, agentes
as $fn$
with entrada as (
  select nullif(btrim(p_rota), '')  as rota,
         nullif(btrim(p_canal), '') as canal
),
-- Taxonomia canonica do Router. Fechada. `ja_comprou` e `desconhecido` nao sao rotas.
rota_valida as (
  select e.rota
    from entrada e
   where e.rota in ('summit_b2c','summit_b2b','institute','dash',
                    'cliente_suporte','concierge_summit')
),
-- Canais canonicos vivos. Sem alias: 'web' nao e canal.
canal_valido as (
  select e.canal
    from entrada e
   where e.canal in ('whatsapp','mindagent-web')
),
-- PLAYBOOK — lido do sistema, nunca fixo aqui. Disponivel so quando a linha
-- existe, esta ativa e tem conteudo: um playbook vazio nao ensina nada.
playbook as (
  select exists (
    select 1 from agentes.prompts pr, entrada e
     where pr.chave = 'playbook_' || e.rota
       and pr.ativo
       and btrim(coalesce(pr.conteudo, '')) <> ''
  ) as tem
),
-- KIT — deixa de ser retrato manual. A verdade de completude do Kit tem um
-- dono so: public.mind_kit_meta. O Gate le, nao re-deriva. Rota invalida faz
-- mind_kit_meta devolver {ok:false,motivo:'rota_invalida'}, sem a chave
-- kit_disponivel; o coalesce transforma isso em false e o CASE final ja
-- responde rota_invalida antes de qualquer reason.
kit as (
  select coalesce(
           (public.mind_kit_meta((select rota from rota_valida))
              ->> 'kit_disponivel')::boolean,
           false) as tem
),
-- CANAL — "este runtime executa esta rota autonomamente?". Nao e "este canal
-- alcanca um humano": essa e a pergunta do Passo 14.
--
--   whatsapp        treble-inbound-agent, que compoe playbook por
--                   treble_agent_prompt: as tres rotas comerciais e de
--                   atendimento. Nao faz concierge — sua pilha inteira e venda.
--   mindagent-web   mindagent-chat, concierge de Summit por construcao, com
--                   instrucoes fixas no codigo que dizem explicitamente que ele
--                   nao vende, nao compra e nao altera dados.
canal_executa as (
  select case (select canal from canal_valido)
           when 'whatsapp'      then (select rota from rota_valida)
                                     in ('summit_b2c','summit_b2b','cliente_suporte')
           when 'mindagent-web' then (select rota from rota_valida)
                                     in ('concierge_summit')
         end as tem
),
-- PRECEDENCIA FECHADA: missing_playbook > missing_kit > canal_incompativel.
-- Um unico reason, nunca uma lista. A ordem nao e arbitraria — ela vai do que
-- falta mais fundo para o que falta mais na ponta, e o primeiro e o unico que
-- uma pessoa destrava escrevendo um texto.
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
    -- needs_human e NECESSIDADE, nao mecanismo: "isto nao pode ser concluido
    -- sozinho e precisa de gente". Nao afirma que existe humano alcancavel
    -- neste canal — inclusive em mindagent-web, onde nao ha. Como a
    -- intervencao acontece e o Passo 14.
    'needs_human',   (select reason from avaliado) is not null,
    'reason',        (select reason from avaliado))
end;
$fn$;

-- ACL preservada exatamente como estava (create or replace nao a altera; os
-- comandos abaixo apenas tornam o estado explicito e sao idempotentes).
revoke all on function public.mind_rota_capacidade(text, text)
  from public, anon, authenticated;
grant execute on function public.mind_rota_capacidade(text, text) to service_role;

comment on function public.mind_rota_capacidade(text, text) is
  'Capability Gate. Precedencia fechada: missing_playbook > missing_kit > canal_incompativel. A celula kit le public.mind_kit_meta(rota)->>kit_disponivel — o Gate nao re-deriva completude de Kit e nao conhece fonte alguma. needs_human e necessidade, nao transporte.';
