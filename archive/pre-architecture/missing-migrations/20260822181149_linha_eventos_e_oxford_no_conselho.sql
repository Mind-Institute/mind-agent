-- Nova linha de produto: 'eventos'. O Summit é vertical própria; os demais
-- eventos do Mind (como Oxford no Conselho) não são Summit nem Institute,
-- e estavam sendo classificados como formação do Institute por falta de
-- lugar melhor na lista do HubSpot.
alter table mind.produtos
  drop constraint produtos_linha_check,
  add constraint produtos_linha_check
    check (linha = any (array['summit', 'institute', 'eventos', 'dash', 'outro']));

insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, vende, ativo)
values
  ('mind-oxford-no-conselho', 'Oxford no Conselho', 'evento', 'eventos',
   'Evento do Mind, fora das verticais Summit e Institute.', false, false)
on conflict (codigo) do nothing;
