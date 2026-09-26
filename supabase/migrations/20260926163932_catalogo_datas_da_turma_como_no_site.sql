-- CATÁLOGO: AS DATAS DA TURMA SÃO AS MESMAS QUE O SITE MOSTRA.
--
-- Corrige 20260926153820_catalogo_datas_da_turma_no_painel. Aquela leitura pegava a coluna crua
-- institute.programas.inicia_em/encerra_em, que está vazia em 4 das 6 turmas: o painel mostrava
-- as datas em branco. Os dois sites (Institute e Join) e o kit do agente (mind_kit_institute_catalogo)
-- leem api.programas, que usa a coluna da turma e, quando ela está vazia, o primeiro e o último
-- encontro da turma ou dos programas que a compõem (institute.programa_encontros /
-- programa_composicao). O comentário daquela migration também errava ao dizer que o checkout
-- (api.criar_pedido) lê essas datas: não lê.
--
-- O que muda, e só isto: mind_admin_read_catalogo calcula as datas da turma como api.programas.
-- A edição continua recusando datas de produto com turma (admin_validation:datas_da_turma), e as
-- colunas comeca_em/encerra_em do catálogo continuam sem ser sobrescritas.
--
-- Contrato: tests/catalogo_painel_contract.sql (termina em CATALOGO_OK) confere, produto a produto,
-- que o painel mostra as mesmas datas de api.programas.

create or replace function public.mind_admin_read_catalogo(p_id uuid default null)
returns jsonb
language sql
stable
security definer
set search_path to 'pg_catalog', 'public', 'catalogo'
as $fn$
  select coalesce(jsonb_agg(x.obj order by x.vertical nulls first, x.nome), '[]'::jsonb)
  from (
    select p.vertical, p.nome,
      jsonb_build_object(
        'id', p.id::text,
        'codigo', p.codigo,
        'nome', p.nome,
        'tipo', p.tipo,
        'vertical', p.vertical,
        'categoria', p.categoria,
        'descricaoCurta', p.descricao_curta,
        'descricao', p.descricao,
        'ativo', p.ativo,
        'vende', p.vende,
        'vendeDe', p.vende_de,
        'vendeAte', p.vende_ate,
        -- Produto com turma no Institute mostra as datas da turma, que são as que valem.
        'comecaEm', case when t.codigo is null then p.comeca_em else t.inicia_em end,
        'encerraEm', case when t.codigo is null then p.encerra_em else t.encerra_em end,
        'datasDaTurma', case when t.codigo is null then null
                             else jsonb_build_object('programa', t.codigo, 'inicioPrevisto', t.inicio_previsto) end,
        'periodo', p.periodo,
        'schemaDados', p.schema_dados,
        'pipelinesHubspot', coalesce(to_jsonb(p.pipelines_hubspot), '[]'::jsonb),
        'atualizadoEm', p.atualizado_em
      ) as obj
    from catalogo.produtos p
    -- A turma do produto: a ativa primeiro, depois a que começa antes.
    left join lateral (
      select pr.codigo, pr.inicio_previsto,
             coalesce(pr.inicia_em, e.primeiro) as inicia_em,
             coalesce(pr.encerra_em, e.ultimo) as encerra_em
        from institute.programas pr
        -- Mesmo cálculo de api.programas (o que os sites e o agente leem): a data da turma e,
        -- vazia, o primeiro e o último encontro dela ou dos programas que a compõem.
        cross join lateral (
          select min((en.acontece_em at time zone 'America/Sao_Paulo')::date) as primeiro,
                 max((en.acontece_em at time zone 'America/Sao_Paulo')::date) as ultimo
            from institute.programa_encontros en
           where en.programa_codigo = pr.codigo
              or en.programa_codigo in (select c.item_codigo
                                          from institute.programa_composicao c
                                         where c.programa_codigo = pr.codigo)
        ) e
       where pr.produto_codigo = p.codigo
       order by pr.ativo desc, coalesce(pr.inicia_em, e.primeiro) nulls last, pr.ordem nulls last, pr.codigo
       limit 1
    ) t on true
    where p_id is null or p.id = p_id
  ) x;
$fn$;

revoke all on function public.mind_admin_read_catalogo(uuid) from public, anon, authenticated;
grant execute on function public.mind_admin_read_catalogo(uuid) to service_role;
