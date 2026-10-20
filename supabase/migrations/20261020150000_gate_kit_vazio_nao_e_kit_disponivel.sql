-- O GATE DEIXA DE DIZER "KIT DISPONÍVEL" SOBRE UM KIT SEM NADA PARA VENDER.
--
-- O problema, medido em produção em 20/10/2026:
--
--   mind_rota_capacidade('summit_b2c','whatsapp') -> reason: missing_kit
--   mind_rota_capacidade('summit_b2b','whatsapp') -> reason: canal_incompativel
--
-- As duas rotas estão fechadas, mas por motivos diferentes — e a diferença não é de
-- política, é de FORMA DO PAYLOAD. `mind_kit_meta` considera um bloco obrigatório
-- presente quando o provedor devolve qualquer coisa que não seja NULL. Os dois
-- provedores de oferta discordam sobre como dizer "não há oferta":
--
--   public.mind_kit_ofertas      (B2C) -> NULL
--   public.mind_kit_ofertas_b2b         -> {"ofertas": [], "pode_vender": false, ...}
--
-- Então o B2C reprova no Kit e o B2B passa, com `kit_disponivel: true` sobre um kit
-- cuja própria resposta é `pode_vender: false`. Hoje o que segura o B2B é só o flag
-- de canal: reativar `whatsapp/summit_b2b` em `agentes.canal_competencia` faria o
-- Gate responder `pode_executar: true`, e o agente rodaria um turno de venda com
-- lista de ofertas vazia. O guardrail de preço impediria preço inventado — payload
-- sem fato monetário não autoriza valor nenhum —, então degradaria para resposta sem
-- preço em vez de preço errado. Mesmo assim, um Gate que afirma "kit disponível"
-- sobre um kit vazio é uma garantia que não garante, e é ele que o runtime consulta
-- para decidir se executa.
--
-- A REGRA, e por que é esta: o bloco já publica a própria resposta. `pode_vender` é
-- campo do contrato dos provedores comerciais, não invenção desta migration — em
-- 20/10/2026, dos 12 provedores obrigatórios das seis rotas, exatamente dois o
-- emitem (`mind_kit_ofertas_b2b` e `mind_kit_precos_por_volume_b2b`), e ambos com
-- `false`. Nenhum outro bloco tem a chave, então nenhuma outra rota muda de estado.
--
-- Não se inventa heurística de vazio: não se olha `ofertas: []`, porque "lista vazia"
-- significa coisas diferentes em blocos diferentes, e um bloco informacional pode
-- legitimamente vir sem itens. Lê-se o que o provedor DECLARA.
--
-- Efeito esperado, conferido contra produção antes de aplicar:
--   summit_b2b/whatsapp  canal_incompativel -> missing_kit   (continua fechado)
--   summit_b2c           missing_kit        -> missing_kit   (sem mudança)
--   institute, dash, cliente_suporte, concierge_summit       (sem mudança)
--
-- Nada é reativado por esta migration e nenhuma rota passa a executar por causa dela:
-- ela só FECHA um caminho que estava aberto por acidente de forma.

create or replace function public.mind_kit_meta(p_rota text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public', 'agentes'
as $function$
declare
  v_rota         text    := nullif(btrim(p_rota), '');
  v_configurado  boolean;
  v_obrigatorios text[]  := array[]::text[];
  v_ausentes     text[]  := array[]::text[];
  v_payload      jsonb;
  r              record;
begin
  if v_rota is null or v_rota not in (
       'summit_b2c','summit_b2b','institute','dash','cliente_suporte','concierge_summit') then
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
      -- Bloco ausente por não existir (NULL) OU por declarar que não há o que vender.
      -- Um bloco obrigatório que responde `pode_vender: false` não sustenta a rota.
      if v_payload is null
         or (v_payload ? 'pode_vender' and (v_payload ->> 'pode_vender') = 'false') then
        v_ausentes := v_ausentes || r.bloco;
      end if;
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
$function$;

comment on function public.mind_kit_meta(text) is
  'Capability Gate — disponibilidade do Kit por rota. Bloco obrigatório conta como '
  'ausente quando o provedor devolve NULL ou declara pode_vender=false.';
