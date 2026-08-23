-- De-para entre o vocabulário do HubSpot e o catálogo de produtos.
-- É tabela, não código: quando o marketing criar uma opção nova no
-- HubSpot, alguém acrescenta uma linha aqui — sem mexer no sincronizador.
create table if not exists crm.mapa_produtos (
  propriedade text not null,      -- propriedade do HubSpot
  valor_origem text not null,     -- valor exato lá (rótulo da opção)
  produto_codigo text not null references mind.produtos(codigo),
  primary key (propriedade, valor_origem)
);

comment on table crm.mapa_produtos is
  'Traduz valores do HubSpot para codigos do catalogo mind.produtos. Valor sem tradução aparece em sync_estado.ignorados em vez de virar produto inventado.';

insert into crm.mapa_produtos (propriedade, valor_origem, produto_codigo) values
  ('summit__categoria_2026', '*', 'mind-summit-2026'),
  ('summit__categoria_2025', '*', 'mind-summit-2025'),
  ('journey__turma_ano', '2025', 'mind-journey-2025'),
  ('formacao__produtos_comprados', 'Formação Gestão Saúde Mental (Adriana - F1)', 'mind-institute-f1-gestao-saude-mental-2025'),
  ('formacao__produtos_comprados', 'Formação Segurança Psicológica (Elaine F2)', 'mind-institute-f2-seguranca-psicologica-2025'),
  ('formacao__produtos_comprados', 'Formacao Significado no Trabalho (Tamara - F3)', 'mind-institute-f3-significado-trabalho-2025'),
  ('formacao__produtos_comprados', 'Certificação Liderança Positiva (F1 + F2 +F3)', 'mind-institute-certificacao-lideranca-positiva-2025'),
  ('formacao__produtos_comprados', 'Mind Journey', 'mind-journey-2025'),
  ('formacao__produtos_comprados', 'Oxford no Conselho', 'mind-oxford-no-conselho')
on conflict do nothing;

alter table crm.mapa_produtos enable row level security;
