-- ============================================================
-- catalogo — registro de produtos na raiz, fora de qualquer vertical
-- ============================================================
-- O catálogo estava dentro de `mind`, um esquema específico. Mas ele é
-- justamente o mapa que qualquer agente consulta antes de saber para
-- onde ir: "Oxford no Conselho? Vertical eventos, dados no esquema X".
-- Um mapa que mora dentro de um dos territórios que ele mapeia não serve
-- a quem ainda não sabe em qual território está.
--
-- A tabela é MOVIDA (não copiada): chaves estrangeiras e dados seguem
-- junto, e nenhum vocabulário de produto é duplicado.

create schema if not exists catalogo;

alter table mind.produtos set schema catalogo;
alter table mind.produto_componentes set schema catalogo;

-- Onde vive o conhecimento de cada produto. É o que transforma o catálogo
-- em roteador: o agente descobre o produto aqui e sabe onde aprofundar.
alter table catalogo.produtos
  add column if not exists schema_dados text,
  add column if not exists descricao text,
  add column if not exists periodo text;

comment on schema catalogo is
  'Registro de produtos do Mind, na raiz e fora das verticais. Todos os agentes consultam aqui para identificar um produto e descobrir onde estao seus dados.';
comment on table catalogo.produtos is
  'Um registro por produto do Mind. Fonte unica do vocabulario de produto: CRM, conhecimento e agentes referenciam estes codigos.';
comment on column catalogo.produtos.linha is
  'Vertical do produto: summit, institute, eventos, dash, outro.';
comment on column catalogo.produtos.schema_dados is
  'Esquema onde vivem os dados e o conhecimento deste produto. Vazio = ainda nao existe base propria.';
comment on column catalogo.produtos.periodo is
  'Quando o produto aconteceu ou acontece, em texto legivel. Ex.: "outubro de 2025".';

-- Compatibilidade: a outra frente já consulta mind.produtos. A visão
-- mantém esse caminho funcionando (é atualizável, por ser visão simples
-- de uma tabela só) enquanto as referências migram.
create or replace view mind.produtos as select * from catalogo.produtos;
comment on view mind.produtos is
  'Compatibilidade: o catalogo agora vive em catalogo.produtos. Prefira o novo caminho.';

-- Onde cada produto tem conhecimento hoje. Summit 2026 e 2025 vivem no
-- esquema `mind` (sessoes, palestrantes, knowledge_documents). Os demais
-- ainda nao tem base propria — fica vazio em vez de apontar para o nada.
update catalogo.produtos set schema_dados = 'mind'
 where codigo in ('mind-summit-2026', 'mind-summit-2025');

update catalogo.produtos
   set periodo = 'outubro de 2025',
       descricao = 'Encontro do Mind sobre conselhos de administracao, realizado uma unica vez, em outubro de 2025.'
 where codigo = 'mind-oxford-no-conselho';

update catalogo.produtos set periodo = '16 e 17 de setembro de 2026' where codigo = 'mind-summit-2026';
update catalogo.produtos set periodo = '2025' where codigo in (
  'mind-summit-2025', 'mind-journey-2025',
  'mind-institute-f1-gestao-saude-mental-2025',
  'mind-institute-f2-seguranca-psicologica-2025',
  'mind-institute-f3-significado-trabalho-2025',
  'mind-institute-certificacao-lideranca-positiva-2025');
