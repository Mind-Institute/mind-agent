-- Regra #1 (D5/D6): as três tabelas de pesquisa entram na regra pela porta oficial.
-- Toda linha passa a ter mind_id resolvido pelo trigger zz_d5_pessoa_antes_de_escrever
-- (mind_identidade_resolver), com mind_id_criterio e mind_id_resolvido_em.
-- 2024/2025: só o e-mail (o campo de WhatsApp é texto livre com nome misturado).
-- Interesse 2025: e-mail e, quando a pessoa deixou, o WhatsApp da pergunta de contato.
select public.mind_pessoa_ligar_tabela('engagement.pesquisa_summit_2024', '{"emails":["email_informado"]}');
select public.mind_pessoa_ligar_tabela('engagement.pesquisa_summit_2025', '{"emails":["email_informado"]}');
select public.mind_pessoa_ligar_tabela('engagement.pesquisa_interesse_2025',
  '{"emails":["email_informado"],"telefones":["respostas.QID26_2_TEXT · contato - Sim, pelo WhatsApp abaixo: - Texto"]}');
