-- Adriana (26/09): "Márcio Atalla não foi, pode tirar." Ele estava em
-- ecossistema.palestrantes_especialistas (id 28, slug marcio-atalla) sem nenhuma sessão do Summit
-- 2026 e sem perfil público; só entrava na contagem de palestrantes do contexto do agente do
-- WhatsApp (treble_agent_context_base). Sai do cadastro, desde que nada aponte para ele. A foto
-- no storage (palestrantes/marcio.webp) não é tocada. Idempotente.
delete from ecossistema.palestrantes_especialistas p
 where p.slug = 'marcio-atalla'
   and not exists (select 1 from summit_2026.session_speakers ss where ss.speaker_id = p.id)
   and not exists (select 1 from ecossistema.perfis_publicos pp where pp.palestrante_especialista_id = p.id);
