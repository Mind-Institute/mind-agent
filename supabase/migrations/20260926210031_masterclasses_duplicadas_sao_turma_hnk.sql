-- Adriana (26/09): as 4 masterclasses aparecem duas vezes no app por causa da turma HNK, não da
-- Vale, como estava escrito em 20260923150000 e 20260923190000. Corrige a descrição da coluna.
comment on column summit_2026.sessions.yazo_ids is
  'IDs desta mesma sessão no app Yazo (export schedules/bookmarks). Mais de um id quando a sessão foi duplicada no app por turma de inscrição - caso das 4 masterclasses (turma HNK x demais). yazo_id (singular) segue sendo o id canônico único e continua vazio.';
