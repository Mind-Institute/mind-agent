-- Correção: o Journey é parte do Mind Institute, não uma linha à parte.
-- Reclassifica a turma de 2025 e devolve a lista de linhas ao original.
update mind.produtos
   set linha = 'institute', atualizado_em = now()
 where codigo = 'mind-journey-2025';

alter table mind.produtos
  drop constraint produtos_linha_check,
  add constraint produtos_linha_check
    check (linha = any (array['summit', 'institute', 'dash', 'outro']));
