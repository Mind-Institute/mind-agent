-- Adriana (26/09): Daiana Garbin foi palestrante do Mind Summit 2024; fica no cadastro de
-- palestrantes, mas sem nenhuma ligação com o Summit 2026. Desfaz 20260926204556, que a removeu
-- por engano. Volta com o mesmo id (14), o slug e a foto de antes (seed de 20260903183000) e, em
-- quem_e, a bio do site do Summit (Mind-Institute/mindsummit2026, src/data/speakers.json). O dossiê
-- longo que ela tinha (carregado fora de migration) não existe em outra fonte do banco e não foi
-- recuperado. Não entra em summit_2026.session_speakers. Idempotente.
insert into ecossistema.palestrantes_especialistas (id, nome, slug, foto_asset, destaque, quem_e)
overriding system value
select 14, 'Daiana Garbin', 'daiana-garbin', 'palestrantes/daiana.webp', false,
       'Jornalista, escritora e criadora de conteúdo, é uma das vozes mais reconhecidas no debate sobre saúde mental, transtornos alimentares e as pressões da vida contemporânea. Autora de Fazendo as Pazes com o Corpo e A Vida Perfeita Não Existe, transforma experiências pessoais e informação qualificada em conversas que ajudam a romper tabus.'
 where not exists (select 1 from ecossistema.palestrantes_especialistas where slug = 'daiana-garbin' or id = 14);
