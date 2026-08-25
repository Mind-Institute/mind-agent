-- 20260825055151_vertical_produto_reconhecimento
--
-- Vertical = de qual frente a pessoa veio (summit/institute/eventos/dash).
-- O produto especifico (ingresso/experiencia/delegacao/patrocinio) so se conhece
-- depois, na conversa/deal. A entrada/site carrega a VERTICAL, nao o produto.
--
-- Classe C (schema). Aplicada no projeto mind-agent (ymnmotgglsrxmjmonwjz).
-- Reversivel (ver bloco ROLLBACK no fim). Blast radius verificado: nenhum
-- consumidor de codigo le a coluna; as 2 funcoes que dependem dela
-- (crm.buscar_pessoa, public.mind_calendario) leem via a view de compat
-- mind.produtos, que segue expondo o nome antigo -> nao quebram.

-- 1) CATALOGO: "linha" sempre foi a vertical. Passa a se chamar vertical.
alter table catalogo.produtos rename column linha to vertical;
alter table catalogo.produtos rename constraint produtos_linha_check to produtos_vertical_check;
comment on column catalogo.produtos.vertical is
  'Vertical (frente) do produto: summit, institute, eventos, dash, outro. A entrada/site carrega a vertical; o produto especifico so se conhece na conversa/deal.';

-- 2) RECONHECIMENTO (intelligence.sinais_comerciais): guarda a vertical de onde a
--    pessoa veio (derivada do dominio do hs_analytics_first_url). produto_codigo
--    continua sendo o produto especifico, preenchido so quando conhecido.
alter table intelligence.sinais_comerciais
  add column vertical text
  check (vertical in ('summit','institute','eventos','dash','outro'));
comment on column intelligence.sinais_comerciais.vertical is
  'Vertical de onde a pessoa veio (summit/institute/eventos/dash), derivada da origem/first_url. Diferente de produto_codigo (produto especifico, preenchido so quando conhecido).';

-- ROLLBACK:
--   alter table intelligence.sinais_comerciais drop column vertical;
--   alter table catalogo.produtos rename constraint produtos_vertical_check to produtos_linha_check;
--   alter table catalogo.produtos rename column vertical to linha;
