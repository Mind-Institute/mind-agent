-- ============================================================================
-- D5.5 — Reservas_Agenda_APP e Check Ins Summit entram na Regra #1
-- ============================================================================
-- As duas tabelas nasceram fora da porta única (migrations reservas_agenda_app_* e
-- check_ins_summit_*, 23/09), com pessoa_id resolvido pela fonte primária
-- (credenciamento_summit_2026.participantes) e SEM chave estrangeira para
-- pessoas.pessoas — por isso a fusão da fase B não as repontou (727 e 297 linhas
-- apontavam para pessoas já fundidas). Aqui: pessoa_id fundida -> sobrevivente;
-- FK para pessoas.pessoas (a fusão passa a repontar); trigger D5 com o mapa
-- Email / Nome / participante_id (= credenciamento). A pedido da Adriana (23/09).
-- Depois desta migration, as linhas sem pessoa (3.112 reservas, 1.811 check-ins)
-- passaram pela porta com mind_identidade_criar_faltantes: 100% ligadas, 0 criadas.
-- ============================================================================
update credenciamento_summit_2026."Reservas_Agenda_APP" r
   set pessoa_id = public.mind_pessoa_canonica(r.pessoa_id)
 where r.pessoa_id is not null
   and exists (select 1 from pessoas.pessoas p where p.id = r.pessoa_id and p.fundida_em is not null);
update credenciamento_summit_2026."Check Ins Summit" c
   set pessoa_id = public.mind_pessoa_canonica(c.pessoa_id)
 where c.pessoa_id is not null
   and exists (select 1 from pessoas.pessoas p where p.id = c.pessoa_id and p.fundida_em is not null);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'reservas_agenda_app_pessoa_fk') then
    alter table credenciamento_summit_2026."Reservas_Agenda_APP"
      add constraint reservas_agenda_app_pessoa_fk foreign key (pessoa_id) references pessoas.pessoas(id);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'check_ins_summit_pessoa_fk') then
    alter table credenciamento_summit_2026."Check Ins Summit"
      add constraint check_ins_summit_pessoa_fk foreign key (pessoa_id) references pessoas.pessoas(id);
  end if;
  perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026."Reservas_Agenda_APP"',
    '{"emails":["Email"],"nome":["Nome"],"credenciamento_id":"participante_id"}');
  perform public.mind_pessoa_ligar_tabela('credenciamento_summit_2026."Check Ins Summit"',
    '{"emails":["Email"],"nome":["Nome"],"credenciamento_id":"participante_id"}');
end $$;

do $$
declare n int;
begin
  select count(*) into n from pg_trigger t join pg_class c on c.oid = t.tgrelid
   where t.tgname = 'zz_d5_pessoa_antes_de_escrever' and not t.tgisinternal and t.tgenabled <> 'D'
     and c.relname in ('Reservas_Agenda_APP','Check Ins Summit');
  if n <> 2 then raise exception 'd5.5: esperava o trigger nas duas tabelas, achei %', n; end if;
  if exists (select 1 from credenciamento_summit_2026."Reservas_Agenda_APP" r join pessoas.pessoas p on p.id = r.pessoa_id where p.fundida_em is not null)
     or exists (select 1 from credenciamento_summit_2026."Check Ins Summit" r join pessoas.pessoas p on p.id = r.pessoa_id where p.fundida_em is not null) then
    raise exception 'd5.5: ainda ha pessoa_id apontando para pessoa fundida';
  end if;
end $$;
