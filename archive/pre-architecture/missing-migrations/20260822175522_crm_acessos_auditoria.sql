-- Auditoria própria do espelho de CRM.
-- concierge.acessos_dado_pessoal audita mind.people (participante do
-- evento, identidade Yazo) e tem chave estrangeira para lá. O espelho do
-- CRM é outra população — todo contato e lead, tenha ou não vindo ao
-- evento — então ganha o próprio registro em vez de afrouxar aquela.
create table if not exists crm.acessos (
  id bigserial primary key,
  funcao text not null,
  pessoa_id uuid references crm.pessoas(id) on delete set null,
  agente text not null,
  criado_em timestamptz not null default now()
);

comment on table crm.acessos is
  'Trilha de quem consultou dado individual do espelho de CRM: qual função, sobre quem, por qual agente.';

create index if not exists crm_acessos_pessoa_idx on crm.acessos (pessoa_id, criado_em desc);

alter table crm.acessos enable row level security;

create or replace function crm.buscar_pessoa(
  p_email text default null,
  p_whatsapp text default null,
  p_agente text default 'desconhecido'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'crm'
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

  select * into v_pessoa from crm.pessoas
   where (v_email is not null and email = v_email)
   limit 1;

  if not found then
    select * into v_pessoa from crm.pessoas
     where (v_whats is not null and whatsapp = v_whats)
     limit 1;
  end if;

  if not found then
    return jsonb_build_object('encontrado', false, 'motivo', 'nao_cadastrado');
  end if;

  insert into crm.acessos (funcao, pessoa_id, agente)
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
