-- Adriana (26/09): "Sobreviver sem destruir o time" (17/09, 15:00-16:00, Arena LinkedIn, app
-- 1035, d2-1500-sobreviver-destruir) foi de Ivana Moreira, Ricardo Souza e Caito Maia, conforme a
-- tela de edição da programação no app. Caito Maia já estava ligado. Ricardo Souza não existia no
-- cadastro; entra com a bio do site (src/data/speakers.json). Ivana Moreira já existe e fica como
-- está. Papel vem do site (src/data/programacao.json): "Caito Maia, Ricardo Souza · Mediação: Ivana
-- Moreira". O tipo segue 'palestra', como o site decidiu em 14/09. Idempotente.
insert into ecossistema.palestrantes_especialistas (nome, slug)
select 'Ricardo Souza', 'ricardo-souza'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'ricardo-souza');

update ecossistema.palestrantes_especialistas
   set quem_e = 'Empreendedor e um dos fundadores do Grupo Movile, empresa por trás de grandes histórias de sucesso como iFood, Sympla, PlayKids e Leitura. Construiu sua trajetória liderando pessoas e negócios em cenários de crescimento acelerado, decisões complexas e alta pressão — sempre com o fator humano no centro dos resultados. Hoje é fundador da BÜ, criadora do Maker, um sistema operacional empresarial com inteligência artificial. Para Ricardo, a tecnologia não substitui pessoas: amplia sua capacidade de pensar, decidir e realizar.',
       atualizado_em = now()
 where slug = 'ricardo-souza'
   and quem_e is distinct from 'Empreendedor e um dos fundadores do Grupo Movile, empresa por trás de grandes histórias de sucesso como iFood, Sympla, PlayKids e Leitura. Construiu sua trajetória liderando pessoas e negócios em cenários de crescimento acelerado, decisões complexas e alta pressão — sempre com o fator humano no centro dos resultados. Hoje é fundador da BÜ, criadora do Maker, um sistema operacional empresarial com inteligência artificial. Para Ricardo, a tecnologia não substitui pessoas: amplia sua capacidade de pensar, decidir e realizar.';

insert into summit_2026.session_speakers (sessao_id, speaker_id, papel)
select s.id, p.id, case when p.slug = 'ivana-moreira' then 'mediacao' else 'palestrante' end
  from summit_2026.sessions s, ecossistema.palestrantes_especialistas p
 where s.site_session_id = 'd2-1500-sobreviver-destruir'
   and p.slug in ('ivana-moreira', 'ricardo-souza')
on conflict do nothing;
