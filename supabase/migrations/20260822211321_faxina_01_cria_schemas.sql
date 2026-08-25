-- Faxina do banco, passo 1: as casas vazias.
-- Nao move nada, nao quebra nada. Deixa os passos seguintes serem pequenos.

create schema if not exists engagement;    -- o que aconteceu com a pessoa
create schema if not exists intelligence;  -- o que a gente infere sobre ela
create schema if not exists comum;         -- o que os produtos reusam
create schema if not exists summit;        -- Mind Summit, todas as edicoes
create schema if not exists institute;     -- formacoes e Journey
create schema if not exists dash;          -- Mind Dash
create schema if not exists eventos;       -- eventos fora do Summit
create schema if not exists quarentena;    -- o que ninguem sabe explicar

comment on schema engagement   is 'O que aconteceu com a pessoa: conversas, mensagens, presencas, identidades de canal, atribuicao, feedback.';
comment on schema intelligence is 'O que a gente infere sobre a pessoa: memoria, objetivos, preferencias, sinais. Declarado x inferido fica explicito aqui.';
comment on schema comum        is 'O que os produtos reusam: palestrantes, taxonomia, materiais, conhecimento institucional.';
comment on schema summit       is 'Mind Summit. Edicao e linha, escopada por event_id.';
comment on schema institute    is 'Mind Institute: formacoes e Journey. Turma e linha.';
comment on schema dash         is 'Mind Dash.';
comment on schema eventos      is 'Eventos fora do Summit, inclusive os fechados de captacao de lead.';
comment on schema quarentena   is 'REVISAR: tabelas sem proposito conhecido. Nada le daqui. Nao apagar sem decisao.';

-- Mesmo padrao de acesso que mind e concierge ja usam.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'mind_agent') then
    grant usage on schema engagement, intelligence, comum, summit, institute, dash, eventos to mind_agent;
  end if;
end $$;
