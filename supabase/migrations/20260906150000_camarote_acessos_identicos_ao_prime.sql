-- Camarote entra na Intelligence com os mesmos acessos do Prime.
--
-- Pedido da Adriana em 06/09/2026: "Coloque na inteligência do mind Summit 2026 os
-- acessos da experiência camarote = idêntico do prime então repita idêntico."
--
-- Estrutura conferida antes de mexer (para não atrapalhar o que já funciona):
--   - `summit_2026.experiencias` tem só 5 colunas (chave, nome, ordem, inclusoes,
--     sincronizado_em); toda a prosa (descrição, posicionamento, proposta de valor)
--     mora DENTRO de `inclusoes`, junto com os grupos de itens;
--   - `public.mind_kit_inclusoes` / `_b2c` fazem scan aberto da tabela (sem lista
--     fechada de chave) — uma linha nova aparece no Kit sem mudança de código;
--   - `public.mind_credenciamento_fatos` já repassa "Camarote" como ticket_type
--     genérico (só recusa a sentinela "SEM MAPA");
--   - nenhum teste em `tests/` lê `summit_2026.experiencias` ao vivo: o fixture de
--     `vendedor_guardrail_preco.mjs` é local ao arquivo e auto-referente (3
--     experiências é o tamanho do próprio fixture, não uma leitura de produção);
--   - `decisioning_vendas_universal` e `playbook_summit_b2b` citam "Mind, VIP e
--     Prime" como exemplo de categorias — prosa ilustrativa, não lista fechada que
--     bloqueia Camarote. Fica registrado como possível atualização futura; não é
--     o que foi pedido aqui, então não mexe.
--
-- "Repita idêntico" = copiar grupos/itens/posicionamento/proposta_de_valor do Prime
-- byte a byte (inclui os rótulos "Prime Lounge", "Masterclasses Prime" e "Fila
-- exclusiva Prime": são o nome de espaço, trilha e fila físicos compartilhados,
-- não um adjetivo do Prime como categoria). Só a `descricao` muda o sujeito de
-- "O Prime" para "O Camarote" — copiá-la sem essa troca faria a própria descrição
-- do Camarote se apresentar como Prime, o que não é "idêntico", é um erro de
-- cópia. Nenhum benefício, valor ou item muda.
--
-- Reversível: delete from summit_2026.experiencias where chave = 'camarote'.
-- Idempotente: só insere se a chave ainda não existir.

begin;

insert into summit_2026.experiencias (chave, nome, ordem, inclusoes, sincronizado_em)
select
  'camarote',
  'Camarote',
  4,
  jsonb_build_object(
    'grupos', p.inclusoes->'grupos',
    'descricao', regexp_replace(p.inclusoes->>'descricao', '^O Prime reúne', 'O Camarote reúne'),
    'posicionamento', p.inclusoes->>'posicionamento',
    'proposta_de_valor', p.inclusoes->>'proposta_de_valor'
  ),
  now()
from summit_2026.experiencias p
where p.chave = 'prime'
  and not exists (select 1 from summit_2026.experiencias where chave = 'camarote');

-- Prova: grupos/posicionamento/proposta_de_valor idênticos ao Prime; só a
-- descrição troca o sujeito, sem sobrar nenhuma menção ao Prime como categoria.
do $$
declare v_prime jsonb; v_camarote jsonb;
begin
  select inclusoes into v_prime from summit_2026.experiencias where chave = 'prime';
  select inclusoes into v_camarote from summit_2026.experiencias where chave = 'camarote';

  if v_camarote is null then raise exception 'camarote não foi inserido'; end if;

  if v_camarote->'grupos' is distinct from v_prime->'grupos' then
    raise exception 'grupos do camarote divergem do prime';
  end if;
  if (v_camarote->>'posicionamento') is distinct from (v_prime->>'posicionamento') then
    raise exception 'posicionamento do camarote diverge do prime';
  end if;
  if (v_camarote->>'proposta_de_valor') is distinct from (v_prime->>'proposta_de_valor') then
    raise exception 'proposta_de_valor do camarote diverge do prime';
  end if;

  if (v_camarote->>'descricao') !~ '^O Camarote reúne' then
    raise exception 'descricao do camarote não troca o sujeito para Camarote';
  end if;
  if (v_camarote->>'descricao') ~ 'O Prime reúne' then
    raise exception 'descricao do camarote ainda se apresenta como Prime';
  end if;

  -- Fora o sujeito da frase, a descrição é idêntica à do Prime.
  if regexp_replace(v_camarote->>'descricao', '^O Camarote reúne', 'O Prime reúne')
       is distinct from (v_prime->>'descricao') then
    raise exception 'descricao do camarote diverge do prime além do sujeito';
  end if;
end $$;

commit;
