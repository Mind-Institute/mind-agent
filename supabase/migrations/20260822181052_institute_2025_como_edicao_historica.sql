-- O Institute inteiro é histórico: nenhuma formação está aberta agora, e a
-- reabertura acontece no Summit. Duas correções:
--
-- 1. Todas as formações de 2025 ficam ativo = false, como as demais
--    edições encerradas do catálogo.
-- 2. O código passa a carregar o ano, seguindo o padrão do Summit
--    (mind-summit-2025 / mind-summit-2026). Sem isso, quando a próxima
--    turma abrir, "quem fez F1" vira uma pergunta sem resposta — e saber
--    quem fez 2025 é justamente o que interessa na reabertura.
--
-- Nada aponta para estes códigos ainda (crm.pessoa_produtos está vazia),
-- então a troca não perde vínculo.

delete from mind.produto_componentes
 where produto_codigo like 'mind-institute-%'
    or componente_codigo like 'mind-institute-%';

delete from mind.produtos
 where codigo in (
   'mind-institute-f1-gestao-saude-mental',
   'mind-institute-f2-seguranca-psicologica',
   'mind-institute-f3-significado-trabalho',
   'mind-institute-certificacao-lideranca-positiva'
 );

insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, vende, ativo)
values
  ('mind-institute-f1-gestao-saude-mental-2025', 'Formacao Gestao de Saude Mental (F1) - 2025',
   'formacao', 'institute',
   'Turma de 2025 da primeira formacao do Mind Institute, sobre gestao de saude mental no trabalho. Encerrada.', false, false),

  ('mind-institute-f2-seguranca-psicologica-2025', 'Formacao Seguranca Psicologica (F2) - 2025',
   'formacao', 'institute',
   'Turma de 2025 da segunda formacao do Mind Institute, sobre seguranca psicologica. Encerrada.', false, false),

  ('mind-institute-f3-significado-trabalho-2025', 'Formacao Significado no Trabalho (F3) - 2025',
   'formacao', 'institute',
   'Turma de 2025 da terceira formacao do Mind Institute, sobre significado no trabalho. Encerrada.', false, false),

  ('mind-institute-certificacao-lideranca-positiva-2025', 'Certificacao Lideranca Positiva - 2025',
   'formacao', 'institute',
   'Certificacao avancada de 2025: combo das tres formacoes (F1 + F2 + F3). Encerrada.', false, false)
on conflict (codigo) do nothing;

insert into mind.produto_componentes (produto_codigo, componente_codigo)
values
  ('mind-institute-certificacao-lideranca-positiva-2025', 'mind-institute-f1-gestao-saude-mental-2025'),
  ('mind-institute-certificacao-lideranca-positiva-2025', 'mind-institute-f2-seguranca-psicologica-2025'),
  ('mind-institute-certificacao-lideranca-positiva-2025', 'mind-institute-f3-significado-trabalho-2025')
on conflict do nothing;
