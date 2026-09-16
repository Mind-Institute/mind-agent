-- Aviso do estacionamento do São Paulo Expo, texto da Adriana (06/09).
--
-- Entra em "Importante Saber Antes do Summit" logo depois de "Como chegar
-- ao São Paulo Expo": aquele aviso já diz que o estacionamento é coberto e
-- tem passarela, e este responde o que faltava — quem administra, que há
-- vaga, e que a cobrança é à parte do ingresso.
--
-- A linha já foi inserida no banco no dia; esta migration existe para o
-- repositório contar a mesma história e para reaplicar sem duplicar. A
-- `chave` é única, então `on conflict` atualiza em vez de criar de novo.
insert into concierge.avisos
  (chave, icone, categoria, situacao, imediato, disparo_em, titulo, subtitulo, descricao)
values (
  'estacionamento',
  'carro',
  'antes_de_ir',
  'no-ar',
  false,
  '2026-09-15 19:10:00+00',
  'Estacionamento',
  'O São Paulo Expo conta com um amplo estacionamento coberto gerido pela Indigo, com vagas disponíveis e acesso direto aos pavilhões São Paulo Expo.',
  'O uso do estacionamento é cobrado separadamente do valor de inscrição ou credenciamento para o Mind Summit.'
)
on conflict (chave) do update set
  icone       = excluded.icone,
  categoria   = excluded.categoria,
  situacao    = excluded.situacao,
  imediato    = excluded.imediato,
  disparo_em  = excluded.disparo_em,
  titulo      = excluded.titulo,
  subtitulo   = excluded.subtitulo,
  descricao   = excluded.descricao,
  arquivado_em = null,
  atualizado_em = now();
