-- Coluna de variações de nome (identidade), para matching e desambiguação.
-- Aditiva e reversível; NULL para quem não tem alias.
alter table ecossistema.palestrantes_especialistas
  add column if not exists aliases text;

comment on column ecossistema.palestrantes_especialistas.aliases is
  'Outras formas do nome da mesma pessoa (ex.: nome de solteira, nome acadêmico), para desambiguação e matching. Texto livre.';
