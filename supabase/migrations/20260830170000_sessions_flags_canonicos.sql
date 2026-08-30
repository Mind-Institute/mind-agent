-- Reconcilia no Git o DDL já aplicado diretamente em produção no rebuild
-- da programação do Mind Summit 2026. Não altera dados.

alter table summit_2026.sessions
  add column if not exists lugares_limitados boolean not null default false;

alter table summit_2026.sessions
  add column if not exists reserva_recomendada boolean not null default false;

comment on column summit_2026.sessions.lugares_limitados is
  'Há limite de lugares/capacidade para esta sessão. Não implica obrigatoriedade de reserva.';

comment on column summit_2026.sessions.reserva_recomendada is
  'É recomendável reservar antes. Reserva é recomendação, não requisito obrigatório de participação.';

comment on column summit_2026.sessions.precisa_reserva is
  'LEGADO DE COMPATIBILIDADE. Não é semântica canônica e não deve ser usado em lógica nova. A semântica vigente é lugares_limitados + reserva_recomendada.';
