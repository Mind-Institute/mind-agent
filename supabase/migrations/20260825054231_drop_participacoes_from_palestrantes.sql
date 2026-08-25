-- Remove a coluna de texto de participação: a participação passa a ser derivada
-- das associações (FK) entre conteúdos e o speaker, não de texto mantido à mão.
-- DESTRUTIVO. Conteúdo anterior preservado no snapshot da conversa (2026-08-25).
-- ROLLBACK:
--   alter table ecossistema.palestrantes_especialistas
--     add column participacoes_no_ecossistema_mind text;
--   (e re-inserir os valores do snapshot, se desejado)
alter table ecossistema.palestrantes_especialistas
  drop column if exists participacoes_no_ecossistema_mind;
