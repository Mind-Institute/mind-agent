-- Casa dos palestrantes e especialistas do ecossistema Mind. Uma pessoa que
-- entrega conhecimento em vários produtos (Summit, Institute...) mora aqui uma
-- vez só, não copiada dentro de cada produto.
-- Recria a table que estava na UI com nome com espaço (vazia: só id/created_at)
-- num nome snake_case, consultável sem aspas.
-- Ordem: identidade -> o que se olha todo dia -> o dossiê -> controle.
drop table if exists ecossistema."Palestrantes e especialistas" cascade;

create table ecossistema.palestrantes_especialistas (
  -- identidade
  id                                        bigint generated always as identity primary key,
  -- o que se olha todo dia
  nome                                      text not null,
  cargo_curto                               text,
  instituicao                               text,
  participacoes_no_ecossistema_mind         text,
  -- o dossiê da pessoa
  quem_e                                    text,
  formacao_e_posicao                        text,
  principais_contribuicoes                  text,
  conceitos_chave_explicados                text,
  por_que_o_conteudo_e_importante           text,
  o_que_posso_esperar_ouvir_e_aprender      text,
  dores_e_problemas_que_ajuda_a_compreender text,
  relevancia_para_os_icps_do_mind           text,
  principais_livros                         text,
  principais_papers                         text,
  limites_e_cuidados_cientificos            text,
  fontes_gerais                             text,
  -- controle
  criado_em                                 timestamptz not null default now(),
  atualizado_em                             timestamptz not null default now()
);

comment on table ecossistema.palestrantes_especialistas is
  'Palestrantes e especialistas do ecossistema Mind. Comum a todos os produtos: a mesma pessoa palestra no Summit e pode dar aula no Institute.';
