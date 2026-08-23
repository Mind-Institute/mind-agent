-- Porta de entrada única dos bots ao espelho de pessoas.
-- Devolve SÓ campos conversáveis: a função não enxerga crm.pessoas_interno,
-- então nenhum ajuste de prompt consegue fazer um bot vazar UTM ou score.
-- Todo acesso a dado individual fica registrado.
create or replace function crm.buscar_pessoa(
  p_email text default null,
  p_whatsapp text default null,
  p_agente text default 'desconhecido'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'crm', 'concierge'
as $$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_whats text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g'), '');
  v_pessoa crm.pessoas%rowtype;
begin
  if v_whats is not null and length(v_whats) between 10 and 11 then
    v_whats := '55' || v_whats;
  end if;

  if v_email is null and v_whats is null then
    return jsonb_build_object('encontrado', false, 'motivo', 'sem_chave');
  end if;

  -- E-mail primeiro: é a chave que o Yazo entrega e a que menos colide.
  select * into v_pessoa from crm.pessoas
   where (v_email is not null and email = v_email)
   limit 1;

  if not found then
    select * into v_pessoa from crm.pessoas
     where (v_whats is not null and whatsapp = v_whats)
     limit 1;
  end if;

  if not found then
    -- Pessoa desconhecida é um lead a coletar, não um erro.
    return jsonb_build_object('encontrado', false, 'motivo', 'nao_cadastrado');
  end if;

  insert into concierge.acessos_dado_pessoal (funcao, sobre, agente)
  values ('crm.buscar_pessoa', v_pessoa.id, coalesce(p_agente, 'desconhecido'));

  return jsonb_build_object(
    'encontrado', true,
    'id', v_pessoa.id,
    'primeiro_nome', v_pessoa.primeiro_nome,
    'sobrenome', v_pessoa.sobrenome,
    'email', v_pessoa.email,
    'whatsapp', v_pessoa.whatsapp,
    'empresa', v_pessoa.empresa,
    'cargo', v_pessoa.cargo,
    'estagio', v_pessoa.estagio,
    'produtos', coalesce((
      select jsonb_agg(jsonb_build_object(
        'produto', p.produto,
        'edicao', p.edicao,
        'categoria', p.categoria,
        'tipo_entrada', p.tipo_entrada,
        'papel', p.papel,
        'quantidade', p.quantidade
      ) order by p.edicao desc nulls last, p.produto)
      from crm.pessoa_produtos p where p.pessoa_id = v_pessoa.id
    ), '[]'::jsonb),
    'dados_de', v_pessoa.sincronizado_em
  );
end;
$$;

comment on function crm.buscar_pessoa is
  'Busca uma pessoa por e-mail ou WhatsApp e devolve apenas campos conversáveis, registrando o acesso. Única via de leitura do espelho pelos bots.';

-- Registrar lead novo: única escrita que os bots fazem na camada de pessoa,
-- e ela cai na caixa de saída, não no espelho.
create or replace function crm.registrar_lead(
  p_email text default null,
  p_whatsapp text default null,
  p_primeiro_nome text default null,
  p_sobrenome text default null,
  p_empresa text default null,
  p_cargo text default null,
  p_agente text default 'desconhecido',
  p_contexto jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'crm'
as $$
declare
  v_email text := nullif(lower(btrim(coalesce(p_email, ''))), '');
  v_whats text := nullif(regexp_replace(coalesce(p_whatsapp, ''), '[^0-9]', '', 'g'), '');
  v_id uuid;
begin
  if v_whats is not null and length(v_whats) between 10 and 11 then
    v_whats := '55' || v_whats;
  end if;

  if v_email is null and v_whats is null then
    return jsonb_build_object('ok', false, 'motivo', 'sem_chave');
  end if;

  insert into crm.leads_capturados
    (email, whatsapp, primeiro_nome, sobrenome, empresa, cargo, agente, contexto)
  values
    (v_email, v_whats, nullif(btrim(coalesce(p_primeiro_nome, '')), ''),
     nullif(btrim(coalesce(p_sobrenome, '')), ''), nullif(btrim(coalesce(p_empresa, '')), ''),
     nullif(btrim(coalesce(p_cargo, '')), ''), coalesce(p_agente, 'desconhecido'),
     coalesce(p_contexto, '{}'::jsonb))
  returning id into v_id;

  return jsonb_build_object('ok', true, 'id', v_id);
end;
$$;

comment on function crm.registrar_lead is
  'Enfileira um lead coletado por um bot para envio ao HubSpot. Não escreve no espelho — o HubSpot devolve a pessoa no próximo sync.';

revoke all on function crm.buscar_pessoa(text, text, text) from public, anon, authenticated;
revoke all on function crm.registrar_lead(text, text, text, text, text, text, text, jsonb) from public, anon, authenticated;
