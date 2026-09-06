-- Prime esgotado: sai de venda, e o sync diário não pode ressuscitá-lo.
--
-- Decisão da Adriana em 06/09/2026: "não estamos mais vendendo ingresso Prime, esgotado".
--
-- O problema real não é marcar `pode_vender = false`; é MANTER a marca. Hoje o cron das
-- 18:00 (jobid 15) lê o percentual do site e recalcula `pode_vender := percentual < 100`.
-- Com o site ainda em 98%, qualquer marcação manual voltaria a `true` na próxima corrida.
-- Esgotado é decisão comercial, não leitura de página — então a decisão precisa vencer o
-- site de forma explícita e auditável.
--
-- Três movimentos, todos na casa que já existe:
--   1. `mindagent_sync_disponibilidade` passa a respeitar um bloco `override` na própria
--      regra `disponibilidade_ingressos`. Como o merge do config é raso (`||`), a chave
--      `override` sobrevive a cada sync sozinha;
--   2. a regra recebe o override do Prime (esgotado, 100%, quem decidiu e quando);
--   3. as três ofertas Prime (lote 7 e os dois upgrades de destino Prime) saem do ar com
--      `ativo = false` — `mind_kit_ofertas` exige `ativo and publico`, então o Prime deixa
--      de existir como checkout para o Vendedor. O UPDATE do sync só toca `ativo = true`,
--      então essas linhas ficam fora do alcance dele também.
--
-- O playbook B2C sobe para v8 com uma linha que torna a orientação dependente de
-- vendabilidade: a §18 nomeava as três experiências, e continuaria oferecendo Prime.
--
-- Reversível: apagar `override->'prime'` e voltar `ativo = true` nas três ofertas.
-- Idempotente: no-op quando já aplicada.

begin;

-- 1. Override manual vence o percentual do site -----------------------------------------
create or replace function public.mindagent_sync_disponibilidade(
  p_vip integer, p_prime integer, p_consultado_em timestamp with time zone default now())
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'summit_2026'
as $function$
declare
  v_vip      integer := p_vip;
  v_prime    integer := p_prime;
  vip_pode   boolean;
  prime_pode boolean;
  cfg        jsonb;
  ov         jsonb;
begin
  if p_vip < 0 or p_vip > 100 or p_prime < 0 or p_prime > 100 then
    raise exception 'percentual fora de 0..100';
  end if;

  select config into cfg
  from summit_2026.commercial_rules
  where chave='disponibilidade_ingressos';

  vip_pode   := v_vip   < 100;
  prime_pode := v_prime < 100;

  -- ESGOTADO É DECISÃO, NÃO LEITURA. Quando a regra tiver `override.<categoria>`, ele vence
  -- o percentual lido do site. Sem sold_percent próprio, esgotado assume 100 — coerente com
  -- a política `pode_vender_se_percentual_menor_que_100`.
  ov := coalesce(cfg->'override', '{}'::jsonb);

  if ov #>> '{vip,pode_vender}' is not null then
    vip_pode := (ov #>> '{vip,pode_vender}')::boolean;
    if not vip_pode then v_vip := coalesce((ov #>> '{vip,sold_percent}')::integer, 100); end if;
  end if;

  if ov #>> '{prime,pode_vender}' is not null then
    prime_pode := (ov #>> '{prime,pode_vender}')::boolean;
    if not prime_pode then v_prime := coalesce((ov #>> '{prime,sold_percent}')::integer, 100); end if;
  end if;

  cfg := coalesce(cfg, '{}'::jsonb)
    || jsonb_build_object(
      'fonte', 'https://mindsummit.com.br/',
      'sincronizacao', jsonb_build_object(
        'frequencia','diaria',
        'horario_local','18:00',
        'timezone','America/Sao_Paulo'
      ),
      'politica', jsonb_build_object(
        'percentual_publico', true,
        'quantidade_absoluta_publica', false,
        'antes_de_upgrade', true,
        'pode_vender_se_percentual_menor_que_100', true,
        'override_vence_o_site', true
      ),
      'categorias', jsonb_build_object(
        'vip', jsonb_build_object(
          'sold_percent', v_vip,
          'pode_vender', vip_pode,
          'fonte_publica', true
        ),
        'prime', jsonb_build_object(
          'sold_percent', v_prime,
          'pode_vender', prime_pode,
          'fonte_publica', true
        )
      ),
      'lido_do_site', jsonb_build_object('vip', p_vip, 'prime', p_prime),
      'consultado_em', p_consultado_em
    );

  update summit_2026.commercial_rules
     set config = cfg,
         atualizado_em = now()
   where chave='disponibilidade_ingressos';

  -- O mesmo dado de categoria aparece tanto no ingresso quanto no upgrade.
  update summit_2026.offers
     set elegibilidade = elegibilidade || jsonb_build_object(
           'disponibilidade', jsonb_build_object(
             'sold_percent', v_vip,
             'pode_vender', vip_pode,
             'fonte', 'https://mindsummit.com.br/'
           )
         ),
         procura_nota = case
           when not vip_pode then v_vip || '% dos lugares VIP vendidos no site. Não oferecer compra nem upgrade VIP. Nunca informar quantidade absoluta restante.'
           else v_vip || '% dos lugares VIP vendidos no site. O percentual pode ser informado; quantidade absoluta restante nunca.'
         end,
         atualizado_em = now()
   where ativo = true
     and elegibilidade->>'categoria' = 'vip';

  update summit_2026.offers
     set elegibilidade = elegibilidade || jsonb_build_object(
           'disponibilidade', jsonb_build_object(
             'sold_percent', v_prime,
             'pode_vender', prime_pode,
             'fonte', 'https://mindsummit.com.br/'
           )
         ),
         procura = case when prime_pode and v_prime >= 98 then 'ultimas_vagas' else procura end,
         procura_nota = case
           when not prime_pode then v_prime || '% dos lugares Prime vendidos no site. Prime esgotado: não oferecer compra nem upgrade Prime. Nunca informar quantidade absoluta restante.'
           when v_prime >= 98 then v_prime || '% dos lugares Prime vendidos no site; o site sinaliza últimos ingressos. Pode informar o percentual ou dizer que os ingressos estão terminando. Nunca informar quantidade absoluta restante.'
           else v_prime || '% dos lugares Prime vendidos no site. O percentual pode ser informado; quantidade absoluta restante nunca.'
         end,
         atualizado_em = now()
   where ativo = true
     and elegibilidade->>'categoria' = 'prime';

  return jsonb_build_object(
    'vip', jsonb_build_object('sold_percent',v_vip,'pode_vender',vip_pode),
    'prime', jsonb_build_object('sold_percent',v_prime,'pode_vender',prime_pode),
    'lido_do_site', jsonb_build_object('vip', p_vip, 'prime', p_prime),
    'override', ov,
    'consultado_em', p_consultado_em
  );
end;
$function$;

-- 2. O override do Prime ----------------------------------------------------------------
update summit_2026.commercial_rules
   set config = config
     || jsonb_build_object(
          'override', coalesce(config->'override','{}'::jsonb) || jsonb_build_object(
            'prime', jsonb_build_object(
              'pode_vender', false,
              'sold_percent', 100,
              'motivo', 'esgotado',
              'definido_por', 'Adriana',
              'definido_em', '2026-09-06'
            )
          ))
     || jsonb_build_object(
          'categorias', coalesce(config->'categorias','{}'::jsonb) || jsonb_build_object(
            'prime', jsonb_build_object('sold_percent', 100, 'pode_vender', false, 'fonte_publica', true)
          )),
       atualizado_em = now()
 where chave = 'disponibilidade_ingressos'
   and produto_codigo = 'mind-summit-2026';

-- 3. As ofertas Prime saem do ar ---------------------------------------------------------
update summit_2026.offers
   set ativo = false,
       procura_nota = 'Prime esgotado em 06/09/2026. Não oferecer compra nem upgrade para Prime.',
       atualizado_em = now()
 where ativo = true
   and elegibilidade->>'categoria' = 'prime';

-- 4. Playbook B2C v7 -> v8: orientar só para o que é vendável -----------------------------
do $$
declare
  v_txt text;
  v_ancora text := 'Descreva cada experiência apenas com o que a Intelligence traz. Benefício que a Intelligence não confirma não entra.';
begin
  select conteudo into v_txt from agentes.prompts where chave='playbook_summit_b2c' and ativo;
  if v_txt is null then raise exception 'playbook_summit_b2c ausente'; end if;

  if (select versao from agentes.prompts where chave='playbook_summit_b2c' and ativo) >= 8 then
    raise notice 'playbook_summit_b2c já em v8 ou superior; nada a fazer';
  else
    if md5(v_txt) <> '17c57ccfeec23cead487d4e1b54bcd37' then
      raise exception 'playbook_summit_b2c v7 divergente do esperado (md5 %)', md5(v_txt);
    end if;
    if (select count(*) from regexp_matches(v_txt, 'Benefício que a Intelligence não confirma não entra\.', 'g')) <> 1 then
      raise exception 'âncora da seção 18 não é única';
    end if;

    v_txt := replace(v_txt, v_ancora, v_ancora || '
Oriente somente para as experiências que a Intelligence mostrar como vendáveis. A que estiver esgotada ou indisponível sai da orientação, da escassez, da condição e do convite. Se a pessoa perguntar diretamente por ela, diga que está esgotada, sem criar expectativa, e siga com o que ainda dá para comprar.');

    update agentes.prompts
       set conteudo = v_txt, versao = 8, atualizado_em = now()
     where chave='playbook_summit_b2c' and ativo;
  end if;
end $$;

-- 5. Provas ------------------------------------------------------------------------------
do $$
declare v jsonb; n int; r jsonb;
begin
  select config into v from summit_2026.commercial_rules
   where chave='disponibilidade_ingressos' and ativo;
  if (v #>> '{override,prime,pode_vender}')::boolean is distinct from false then
    raise exception 'override do Prime ausente';
  end if;
  if (v #>> '{categorias,prime,pode_vender}')::boolean is distinct from false then
    raise exception 'categoria prime ainda vendável';
  end if;

  select count(*) into n from summit_2026.offers
   where ativo and elegibilidade->>'categoria' = 'prime';
  if n <> 0 then raise exception 'ainda há % oferta(s) Prime ativa(s)', n; end if;

  if (select conteudo from agentes.prompts where chave='playbook_summit_b2c' and ativo)
       !~ 'Oriente somente para as experiências que a Intelligence mostrar como vendáveis' then
    raise exception 'linha de vendabilidade ausente no playbook';
  end if;

  -- A prova que importa: o sync das 18:00 rodando com o site ainda em 98% NÃO reabre o Prime.
  select public.mindagent_sync_disponibilidade(78, 98) into r;
  if (r #>> '{prime,pode_vender}')::boolean is distinct from false then
    raise exception 'sync reabriu o Prime: %', r;
  end if;
  if (r #>> '{vip,pode_vender}')::boolean is distinct from true then
    raise exception 'sync fechou o VIP indevidamente: %', r;
  end if;
end $$;

commit;
