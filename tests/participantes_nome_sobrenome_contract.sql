-- ============================================================
-- Contrato: participantes.primeiro_nome / sobrenome derivam de name
-- ============================================================
-- Rodar:  psql "$DATABASE_URL" -f tests/participantes_nome_sobrenome_contract.sql
--
-- Não escreve nada. Abre transação e desfaz no fim, como os outros
-- contratos deste diretório.
--
-- O QUE ESTE CONTRATO GARANTE
-- 1. mind_nome_grafia normaliza a grafia sem inventar nada: espaços,
--    Primeira Letra Maiúscula, partículas em minúscula quando não abrem
--    o nome.
-- 2. mind_nome_dividir usa a mesma regra de mind_identidade_resolver:
--    primeira palavra é o primeiro nome, o resto é sobrenome.
-- 3. O trigger participantes_nome_dividir refaz as duas colunas em toda
--    escrita — inserção (é o que o sync de 30 min faz), troca de name e
--    edição manual das próprias colunas. Editar à mão não segura.
-- 4. Nas linhas que já existem, ninguém está fora da regra.
-- ============================================================

begin;

-- o contrato é sobre o nome, não sobre identidade: a porta D5 fica de fora
set local mind.d5_pular_trigger = '1';

do $$
declare
  r record;
  n int;
  v_id uuid := '00000000-0000-4000-8000-0000000c0de1';
begin
  -- 1. grafia --------------------------------------------------------------
  assert public.mind_nome_grafia(null) is null,  'nulo continua nulo';
  assert public.mind_nome_grafia('') is null,    'vazio vira nulo';
  assert public.mind_nome_grafia('   ') is null, 'só espaço vira nulo';
  assert public.mind_nome_grafia('MARIA DA SILVA') = 'Maria da Silva',
    'maiúsculas viram Primeira Letra, partícula fica minúscula';
  assert public.mind_nome_grafia('joão  batista   dos santos') = 'João Batista dos Santos',
    'espaços repetidos colapsam; acento sobe junto';
  assert public.mind_nome_grafia('  Heloísa Minetto DE Grande ') = 'Heloísa Minetto de Grande',
    'pontas aparadas; DE vira de';
  assert public.mind_nome_grafia('De Paula Souza') = 'De Paula Souza',
    'partícula que abre o nome não é rebaixada';
  assert public.mind_nome_grafia('ana-maria costa') = 'Ana-Maria Costa',
    'hífen separa palavra dentro da palavra';
  assert public.mind_nome_grafia('Maria Cleilsia Falcao de Lima') = 'Maria Cleilsia Falcao de Lima',
    'nome já certo sai igual';

  -- 2. divisão -------------------------------------------------------------
  select * into r from public.mind_nome_dividir('MARIA DA SILVA');
  assert r.primeiro_nome = 'Maria' and r.sobrenome = 'da Silva',
    format('divisão errada: %s | %s', r.primeiro_nome, r.sobrenome);
  select * into r from public.mind_nome_dividir('Madonna');
  assert r.primeiro_nome = 'Madonna' and r.sobrenome is null,
    'uma palavra só: sobrenome nulo';
  select * into r from public.mind_nome_dividir(null);
  assert r.primeiro_nome is null and r.sobrenome is null, 'nulo divide em nulos';
  select * into r from public.mind_nome_dividir('Lindolfo do Espirito Santo de Sousa Filho');
  assert r.primeiro_nome = 'Lindolfo' and r.sobrenome = 'do Espirito Santo de Sousa Filho',
    'tudo depois da primeira palavra é sobrenome';

  -- 3. trigger -------------------------------------------------------------
  insert into credenciamento_summit_2026.participantes (id, name, email)
  values (v_id, 'MARIA   DA SILVA', 'contrato-nome@example.invalid');
  select primeiro_nome, sobrenome into r
    from credenciamento_summit_2026.participantes where id = v_id;
  assert r.primeiro_nome = 'Maria' and r.sobrenome = 'da Silva',
    format('insert não dividiu: %s | %s', r.primeiro_nome, r.sobrenome);

  update credenciamento_summit_2026.participantes set name = 'josé ANTÔNIO dos reis' where id = v_id;
  select primeiro_nome, sobrenome into r
    from credenciamento_summit_2026.participantes where id = v_id;
  assert r.primeiro_nome = 'José' and r.sobrenome = 'Antônio dos Reis',
    format('update de name não refez: %s | %s', r.primeiro_nome, r.sobrenome);

  update credenciamento_summit_2026.participantes set primeiro_nome = 'Zé', sobrenome = null where id = v_id;
  select primeiro_nome, sobrenome into r
    from credenciamento_summit_2026.participantes where id = v_id;
  assert r.primeiro_nome = 'José' and r.sobrenome = 'Antônio dos Reis',
    'edição manual das colunas derivadas não segura';

  update credenciamento_summit_2026.participantes set name = null where id = v_id;
  select primeiro_nome, sobrenome into r
    from credenciamento_summit_2026.participantes where id = v_id;
  assert r.primeiro_nome is null and r.sobrenome is null, 'name nulo limpa as duas';

  -- 4. linhas reais --------------------------------------------------------
  select count(*) into n
    from credenciamento_summit_2026.participantes p
   where p.id <> v_id
     and (p.primeiro_nome is distinct from (public.mind_nome_dividir(p.name)).primeiro_nome
       or p.sobrenome     is distinct from (public.mind_nome_dividir(p.name)).sobrenome);
  assert n = 0, format('%s linha(s) com primeiro_nome/sobrenome fora da regra', n);

  raise notice 'contrato participantes_nome_sobrenome: ok';
end $$;

rollback;
