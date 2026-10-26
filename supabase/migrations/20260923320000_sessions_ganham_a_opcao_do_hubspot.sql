-- O nome de cada workshop/masterclass na propriedade de contato do HubSpot
-- (workshop_masterclass_mind_summit_2026) fica gravado na própria sessão, para
-- que backend e HubSpot casem sem mapa solto em query. Só as 16 sessões de
-- workshop/masterclass têm valor; as demais ficam nulas.
alter table summit_2026.sessions add column if not exists hubspot_opcao text;
comment on column summit_2026.sessions.hubspot_opcao is
  'Valor exato da opção desta sessão na propriedade de contato workshop_masterclass_mind_summit_2026 do HubSpot (checkbox). Nulo = sessão não vai para o HubSpot.';
update summit_2026.sessions s set hubspot_opcao = v.opcao
  from (values
    ('181e4ac2-9be7-4e99-afd5-e68c71981f2a'::uuid,'Workshop - Conversas difíceis, times que crescem'),
    ('086820a8-c16e-4c8a-8d21-6c849cd1c27a','Workshop - Da mensuração ao PGR'),
    ('2f642361-10d5-4ef4-853f-8e3958bb6fa4','Workshop - Falhar melhor'),
    ('fcbd16c9-c575-42d4-bd17-343654f01af0','Workshop - Liderança engajadora'),
    ('3cc1b1c2-7175-4f56-a833-73be386c2518','Masterclass - Mensurar, intervir, provar: a metodologia Oxford para wellbeing como ativo de performance.'),
    ('586055a2-7ae0-49ba-b18a-0c2e2919a176','Workshop - O que sustenta equipes de alta performance'),
    ('2c0c8319-864b-4912-8da5-2afbff68a787','Masterclass - Liderando para liberar a aprendizagem coletiva'),
    ('5de30250-2156-4b00-8580-fe3509b440b0','Workshop - Resiliência em tempo real'),
    ('99f3cb84-5c3e-419c-988c-2e9a6dfc9c96','Masterclass - Bem-estar baseado em evidência'),
    ('f1812042-670c-4bf4-ba15-261dc47f3b75','Workshop - Bem-estar começa na agenda'),
    ('2022a60e-278b-4f25-b373-ec2baaf2103b','Workshop - Navegar a mudança: liderança em contextos de incerteza'),
    ('cd576be2-7893-4aa3-8d9f-54ac59cac292','Workshop - O feedback que falta'),
    ('bf087fb7-81ac-4128-8437-e8faf37d9276','Workshop - O líder como arquiteto do trabalho'),
    ('57ea4989-58cc-45b4-bd3a-839b63d7c300','Masterclass - Os 6 desalinhamentos do burnout'),
    ('cc97285a-d8ad-4c05-85bd-21fa147c1982','Workshop - Riscos psicossociais sem improviso'),
    ('3a9e9698-d7a6-4d9f-9f01-4760f8afd414','Workshop - Trabalho híbrido sem caos')) as v(id, opcao)
 where s.id = v.id;
