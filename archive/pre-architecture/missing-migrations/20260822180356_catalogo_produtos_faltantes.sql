-- O catálogo só conhecia o Summit 2026, mas o CRM tem gente de outras
-- edições e de outra linha de produto. Registra o que existe de fato:
-- Summit 2025 (2.162 pessoas) e Journey 2025 (148 pessoas).
-- Summit 2023/2024 e Institute ficam de fora porque não há um único
-- contato com esses produtos — catalogar produto sem gente é inventar.

-- 'journey' não estava entre as linhas aceitas. É linha de produto real
-- do Mind (comunidade de desenvolvimento, com turmas por ano), então
-- entra na lista em vez de ser classificada como 'outro'.
alter table mind.produtos
  drop constraint produtos_linha_check,
  add constraint produtos_linha_check
    check (linha = any (array['summit', 'institute', 'journey', 'dash', 'outro']));

insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, vende, ativo)
values
  ('mind-summit-2025', 'Mind Summit 2025', 'evento', 'summit',
   'Edicao de 2025 do Mind Summit. Encerrada: nao esta a venda, mas segue referenciavel para quem participou.',
   false, true),
  ('mind-journey-2025', 'Mind Journey 2025', 'assinatura', 'journey',
   'Turma de 2025 do Journey, comunidade de desenvolvimento do Mind, com plano de pagamento recorrente.',
   false, true)
on conflict (codigo) do nothing;
