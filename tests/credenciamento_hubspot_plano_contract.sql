-- ============================================================
-- Contrato: mind_credenciamento_hubspot_plano() — uma pessoa por e-mail,
-- telefone/CPF só de linha própria, reembolso só com a Eduzz
-- ============================================================
-- Rodar:  psql "$DATABASE_URL" -f tests/credenciamento_hubspot_plano_contract.sql
--
-- Não escreve nada. Abre transação e desfaz no fim, como os outros
-- contratos deste diretório. Vale sobre qualquer base: as invariantes
-- são sobre a forma do plano, não sobre quem está nele.
-- ============================================================

begin;

do $$
declare
  n int;
begin
  -- 1. uma linha por e-mail ativo, e nenhum e-mail ativo fica de fora
  select count(*) into n from (
    select lower(btrim(email)) as em from credenciamento_summit_2026.participantes where status = 'ativo'
    except
    select email from public.mind_credenciamento_hubspot_plano() where participante
  ) t;
  assert n = 0, format('%s e-mail(s) ativo(s) fora do plano', n);

  select count(*) - count(distinct email) into n from public.mind_credenciamento_hubspot_plano();
  assert n = 0, format('%s e-mail(s) repetido(s) no plano', n);

  -- 2. quem só foi inscrito por terceiro não sai com telefone nem CPF (D5)
  select count(*) into n from public.mind_credenciamento_hubspot_plano()
   where so_por_terceiro and (telefone is not null or cpf is not null);
  assert n = 0, format('%s linha(s) por terceiro com telefone/CPF', n);

  -- 3. quem não participou não leva telefone, CPF, categoria, origem nem lote
  select count(*) into n from public.mind_credenciamento_hubspot_plano()
   where not participante
     and (telefone is not null or cpf is not null or cardinality(categorias) > 0
          or cardinality(origens) > 0 or cardinality(lotes) > 0 or pagante or cortesia or patrocinio);
  assert n = 0, format('%s linha(s) sem participação carregando dados de ingresso', n);

  -- 4. pagante só participando, com origem Pago
  select count(*) into n from public.mind_credenciamento_hubspot_plano()
   where pagante and (not participante or not ('Pago' = any(origens)));
  assert n = 0, format('%s pagante(s) sem linha Pago', n);

  -- 5. reembolsado nunca é participante, e nunca ao mesmo tempo "não confirmado"
  select count(*) into n from public.mind_credenciamento_hubspot_plano()
   where reembolsado and (participante or reembolso_nao_confirmado);
  assert n = 0, format('%s reembolso(s) inconsistente(s)', n);

  -- 6. formatos: telefone E.164 com +, CPF 11 dígitos, sem 'SEM MAPA' em categorias
  select count(*) into n from public.mind_credenciamento_hubspot_plano()
   where (telefone is not null and telefone !~ '^\+[0-9]{10,15}$')
      or (cpf is not null and cpf !~ '^[0-9]{11}$')
      or ('SEM MAPA' = any(categorias));
  assert n = 0, format('%s linha(s) com formato fora do contrato', n);

  -- 7. só service_role executa
  assert not has_function_privilege('anon', 'public.mind_credenciamento_hubspot_plano()', 'execute'), 'anon executa o plano';
  assert not has_function_privilege('authenticated', 'public.mind_credenciamento_hubspot_plano()', 'execute'), 'authenticated executa o plano';

  raise notice 'contrato credenciamento_hubspot_plano: ok';
end $$;

rollback;
