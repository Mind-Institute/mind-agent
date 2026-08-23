-- mind.produtos é o catálogo canônico de produtos do Mind (codigo, nome,
-- linha, vigência). O espelho de CRM passa a referenciá-lo em vez de
-- guardar 'summit' + '2026' como texto solto: um vocabulário de produto
-- só, mantido por quem cuida do catálogo.
--
-- A tabela está vazia, então a troca não perde dado.
drop table if exists crm.pessoa_produtos;

create table crm.pessoa_produtos (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references crm.pessoas(id) on delete cascade,

  -- Ex.: 'mind-summit-2026'. O código do catálogo já carrega a edição.
  produto_codigo text not null references mind.produtos(codigo),

  categoria text,        -- Mind, VIP, Prime — categoria do ingresso
  tipo_entrada text,     -- pago, cortesia, bônus, patrocínio
  papel text,            -- pagante, participante (podem coexistir)
  quantidade integer check (quantidade is null or quantidade >= 0),

  sincronizado_em timestamptz,
  criado_em timestamptz not null default now(),

  unique (pessoa_id, produto_codigo)
);

comment on table crm.pessoa_produtos is
  'O que cada pessoa já adquiriu, um registro por produto do catálogo mind.produtos. Conversável: a pessoa pode perguntar sobre a própria compra.';
comment on column crm.pessoa_produtos.produto_codigo is
  'Referência ao catálogo mind.produtos. Produto ausente do catálogo bloqueia a carga de propósito: melhor falhar alto que inventar vocabulário.';

create index pessoa_produtos_pessoa_idx on crm.pessoa_produtos (pessoa_id);
create index pessoa_produtos_produto_idx on crm.pessoa_produtos (produto_codigo);

alter table crm.pessoa_produtos enable row level security;

-- A busca devolve o nome do produto junto com o código, para o bot poder
-- dizer "Mind Summit 2026" em vez de repetir um identificador técnico.
create or replace function crm.buscar_pessoa(
  p_email text default null,
  p_whatsapp text default null,
  p_agente text default 'desconhecido'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'crm', 'mind'
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
        'codigo', pp.produto_codigo,
        'nome', pr.nome,
        'linha', pr.linha,
        'categoria', pp.categoria,
        'tipo_entrada', pp.tipo_entrada,
        'papel', pp.papel,
        'quantidade', pp.quantidade
      ) order by pr.comeca_em desc nulls last, pr.nome)
      from crm.pessoa_produtos pp
      join mind.produtos pr on pr.codigo = pp.produto_codigo
      where pp.pessoa_id = v_pessoa.id
    ), '[]'::jsonb),
    'dados_de', v_pessoa.sincronizado_em
  );
end;
$$;
