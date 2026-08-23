-- Mind Institute: as três formações são produtos distintos, e a
-- Certificação Liderança Positiva é o combo das três, vendido em 2025.
-- Nomes conforme a lista oficial do HubSpot (Institute Formações Cursadas).
insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, vende, ativo)
values
  ('mind-institute-f1-gestao-saude-mental', 'Formacao Gestao de Saude Mental (F1)',
   'formacao', 'institute',
   'Primeira formacao do Mind Institute, sobre gestao de saude mental no trabalho.', false, true),

  ('mind-institute-f2-seguranca-psicologica', 'Formacao Seguranca Psicologica (F2)',
   'formacao', 'institute',
   'Segunda formacao do Mind Institute, sobre seguranca psicologica.', false, true),

  ('mind-institute-f3-significado-trabalho', 'Formacao Significado no Trabalho (F3)',
   'formacao', 'institute',
   'Terceira formacao do Mind Institute, sobre significado no trabalho.', false, true),

  ('mind-institute-certificacao-lideranca-positiva', 'Certificacao Lideranca Positiva',
   'formacao', 'institute',
   'Certificacao avancada: combo das tres formacoes (F1 + F2 + F3), vendida em 2025.', false, false)
on conflict (codigo) do nothing;

-- ------------------------------------------------------------
-- Composição de produtos: o combo sabe do que é feito.
-- Sem isso, "tem a certificação" e "cursou as três formações" seriam
-- fatos desconexos, e a carga precisaria embutir essa regra em código.
-- ------------------------------------------------------------
create table if not exists mind.produto_componentes (
  produto_codigo text not null references mind.produtos(codigo) on delete cascade,
  componente_codigo text not null references mind.produtos(codigo) on delete cascade,
  primary key (produto_codigo, componente_codigo),
  constraint componente_nao_e_o_proprio check (produto_codigo <> componente_codigo)
);

comment on table mind.produto_componentes is
  'Quais produtos compoem um combo. Ex.: a Certificacao Lideranca Positiva contem as formacoes F1, F2 e F3.';

insert into mind.produto_componentes (produto_codigo, componente_codigo)
values
  ('mind-institute-certificacao-lideranca-positiva', 'mind-institute-f1-gestao-saude-mental'),
  ('mind-institute-certificacao-lideranca-positiva', 'mind-institute-f2-seguranca-psicologica'),
  ('mind-institute-certificacao-lideranca-positiva', 'mind-institute-f3-significado-trabalho')
on conflict do nothing;
