-- Adriana (26/09): Daiana Garbin não participou do Mind Summit 2026; sai também do cadastro de
-- palestrantes. Ela estava em ecossistema.palestrantes_especialistas (id 14, slug daiana-garbin)
-- sem nenhuma sessão (ligação removida em 20260926204500), sem perfil público e sem menção na base
-- de conhecimento do Summit. Mesmo padrão de 20260926182300 (Márcio Atalla). Idempotente.
-- (Desfeito em 20260926204842: ela foi palestrante de 2024 e fica no cadastro.)
delete from ecossistema.palestrantes_especialistas p
 where p.slug = 'daiana-garbin'
   and not exists (select 1 from summit_2026.session_speakers ss where ss.speaker_id = p.id)
   and not exists (select 1 from ecossistema.perfis_publicos pp where pp.palestrante_especialista_id = p.id);
