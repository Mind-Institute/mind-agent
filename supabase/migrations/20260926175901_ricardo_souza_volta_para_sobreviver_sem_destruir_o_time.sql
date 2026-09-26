-- Adriana (26/09): "pode colocar o Ricardo Souza no painel com o Caito e precisamos incluir a bio".
-- Ricardo Souza volta para "Sobreviver sem destruir o time" (d2-1500-sobreviver-destruir, 17/09
-- 15:00, app 1035) como palestrante, ao lado do Caito Maia, desfazendo 20260926175733. Entra no
-- cadastro com a bio do site (src/data/speakers.json). Ivana Moreira segue na mediação. Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select 'Ricardo Souza', 'ricardo-souza'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'ricardo-souza');

update ecossistema.palestrantes_especialistas
   set quem_e = 'Empreendedor e um dos fundadores do Grupo Movile, empresa por trás de grandes histórias de sucesso como iFood, Sympla, PlayKids e Leitura. Construiu sua trajetória liderando pessoas e negócios em cenários de crescimento acelerado, decisões complexas e alta pressão — sempre com o fator humano no centro dos resultados. Hoje é fundador da BÜ, criadora do Maker, um sistema operacional empresarial com inteligência artificial. Para Ricardo, a tecnologia não substitui pessoas: amplia sua capacidade de pensar, decidir e realizar.',
       atualizado_em = now()
 where slug = 'ricardo-souza'
   and quem_e is distinct from 'Empreendedor e um dos fundadores do Grupo Movile, empresa por trás de grandes histórias de sucesso como iFood, Sympla, PlayKids e Leitura. Construiu sua trajetória liderando pessoas e negócios em cenários de crescimento acelerado, decisões complexas e alta pressão — sempre com o fator humano no centro dos resultados. Hoje é fundador da BÜ, criadora do Maker, um sistema operacional empresarial com inteligência artificial. Para Ricardo, a tecnologia não substitui pessoas: amplia sua capacidade de pensar, decidir e realizar.';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, 'palestrante'
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1500-sobreviver-destruir'
   and p.slug = 'ricardo-souza'
on conflict do nothing;
