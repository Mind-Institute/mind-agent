-- Participantes do credenciamento ganham `primeiro_nome` e `sobrenome`, derivados de
-- `name` com a grafia normalizada. Pedido da Adriana em 23/09/2026, para levar o banco
-- ao HubSpot (firstname / lastname) na direção de D1.
--
-- `name` fica intacta: é o que veio da origem (mind-summit-vendas-dashboard,
-- public.credenciamento_participantes), e o sync a regrava a cada 30 minutos.
--
-- POR QUE TRIGGER, E NÃO EDGE FUNCTION
-- A tabela é espelho: `espelho_gravar('cred_participantes')` apaga e reinsere todas as
-- linhas a cada meia hora (:20 e :50). Qualquer valor gravado por fora sumiria no ciclo
-- seguinte. Um trigger BEFORE INSERT OR UPDATE roda dentro de cada escrita, inclusive a
-- do sync, sem agendamento e sem deploy à parte. É exatamente como `telefone_norm`
-- (participantes_normalizar) e `pessoa_id` (zz_d5_pessoa_antes_de_escrever) já se mantêm
-- nesta tabela. Uma Edge Function teria de ser disparada depois de cada sync e seria mais
-- uma coisa para quebrar, fazendo o mesmo trabalho mais tarde.
--
-- REGRA DE DIVISÃO: a mesma que `mind_identidade_resolver` (D5) já usa para
-- pessoas.pessoas — a primeira palavra é o primeiro nome; todo o resto é sobrenome.
-- Nome de uma palavra só: sobrenome nulo.
--
-- GRAFIA (`mind_nome_grafia`): espaços colapsados; Primeira Letra Maiúscula em cada
-- palavra; partículas (de, da, do, das, dos, e, di, del, della, van, von, der, la, le)
-- em minúscula quando não abrem o nome. Medido em 23/09 nas 2.577 linhas: a regra devolve
-- o próprio `name` em 100% delas — hoje não muda nada, protege o que entrar.
--
-- Idempotente: pode rodar de novo.

-- ---------------------------------------------------------------------------
-- funções puras, em public, ao lado de mind_nome_normalizar / mind_nome_tokens

create or replace function public.mind_nome_grafia(p_nome text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, public
as $$
  select string_agg(
           case
             when u.ord > 1
              and lower(u.palavra) in ('de','da','do','das','dos','e','di','del','della',
                                       'van','von','der','la','le')
               then lower(u.palavra)
             else initcap(u.palavra)
           end,
           ' ' order by u.ord)
    from unnest(string_to_array(
           nullif(btrim(regexp_replace(coalesce(p_nome, ''), '\s+', ' ', 'g')), ''),
           ' ')) with ordinality as u(palavra, ord);
$$;

comment on function public.mind_nome_grafia(text) is
  'Grafia de exibição de um nome de pessoa: espaços colapsados, Primeira Letra Maiúscula em cada palavra, partículas (de, da, dos...) em minúscula quando não abrem o nome. Nulo para vazio. Não confundir com mind_nome_normalizar, que é para comparar, não para mostrar.';

create or replace function public.mind_nome_dividir(
  p_nome text,
  out primeiro_nome text,
  out sobrenome text
)
returns record
language sql
immutable
parallel safe
set search_path = pg_catalog, public
as $$
  select split_part(g.n, ' ', 1),
         nullif(btrim(substr(g.n, length(split_part(g.n, ' ', 1)) + 2)), '')
    from (select public.mind_nome_grafia(p_nome) as n) g;
$$;

comment on function public.mind_nome_dividir(text) is
  'Divide um nome com a grafia de mind_nome_grafia: a primeira palavra é primeiro_nome, o resto é sobrenome (nulo se só houver uma palavra). Mesma regra de mind_identidade_resolver (D5).';

-- ---------------------------------------------------------------------------
-- colunas

alter table credenciamento_summit_2026.participantes
  add column if not exists primeiro_nome text,
  add column if not exists sobrenome     text;

comment on column credenciamento_summit_2026.participantes.primeiro_nome is
  'Primeira palavra de name, com a grafia de mind_nome_grafia. Derivada: o trigger participantes_nome_dividir refaz em toda escrita, inclusive no sync de 30 min — editar à mão não segura. Alimenta firstname no HubSpot (D1).';
comment on column credenciamento_summit_2026.participantes.sobrenome is
  'Tudo depois da primeira palavra de name, com a grafia de mind_nome_grafia. Nulo quando name tem uma palavra só. Derivada como primeiro_nome. Alimenta lastname no HubSpot (D1).';

-- ---------------------------------------------------------------------------
-- trigger: a divisão acontece dentro de cada escrita, inclusive a do sync

create or replace function credenciamento_summit_2026.participantes_nome_dividir()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $$
begin
  select d.primeiro_nome, d.sobrenome
    into new.primeiro_nome, new.sobrenome
    from public.mind_nome_dividir(new.name) d;
  return new;
end $$;

drop trigger if exists participantes_nome_dividir on credenciamento_summit_2026.participantes;
create trigger participantes_nome_dividir
  before insert or update of name, primeiro_nome, sobrenome
  on credenciamento_summit_2026.participantes
  for each row execute function credenciamento_summit_2026.participantes_nome_dividir();

-- ---------------------------------------------------------------------------
-- carga inicial das linhas que já estão aqui. A porta D5 é pulada de propósito: nada de
-- identidade muda nesta escrita, e a chave evita passar 2.577 linhas pela resolução.

set local mind.d5_pular_trigger = '1';

update credenciamento_summit_2026.participantes
   set primeiro_nome = (public.mind_nome_dividir(name)).primeiro_nome,
       sobrenome     = (public.mind_nome_dividir(name)).sobrenome
 where primeiro_nome is distinct from (public.mind_nome_dividir(name)).primeiro_nome
    or sobrenome     is distinct from (public.mind_nome_dividir(name)).sobrenome;
