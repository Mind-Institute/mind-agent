-- 40 — fase B: a decisão. Só o que você aprovar aqui é fundido; nada mais funde ninguém.
-- Troque 'Adriana' pelo seu nome se quiser outra assinatura na auditoria.

-- Aprovar um PADRÃO inteiro: só as propostas de confiança ALTA daquele padrão são
-- fundidas; as de confiança média e baixa continuam pendentes para decisão pelo id.
select public.mind_fusao_decidir('mesmo_email_hubspot_x_login', 'aprovar', 'Adriana');
-- select public.mind_fusao_decidir('mesmo_email_dois_hubspot', 'aprovar', 'Adriana');
-- select public.mind_fusao_decidir('mesmo_email', 'aprovar', 'Adriana');

-- Decidir UMA pendência (o id vem do 30.2):
-- select public.mind_fusao_decidir('00000000-0000-0000-0000-000000000000', 'aprovar', 'Adriana');
-- select public.mind_fusao_decidir('00000000-0000-0000-0000-000000000000', 'rejeitar', 'Adriana');

-- Rejeitar um padrão inteiro (todas as confianças):
-- select public.mind_fusao_decidir('telefone_compartilhado', 'rejeitar', 'Adriana');

-- Depois de fundir, volte ao 11 numa rodada nova (veja o comentário no fim do 11).
