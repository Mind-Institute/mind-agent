-- Regras do Summit 2026 para o pós-evento. Decisão da Adriana em 24/09/2026: o papel do agente
-- agora é "suporte pós-evento + ponte para o Institute"; canal humano pós-evento: WhatsApp
-- (11) 91782-0772, "caso a pessoa precise de suporte humano".
--
-- `mind_kit_evento` leva ao agente, em todo turno do concierge e do suporte, as regras com
-- prioridade <= 2. Até aqui eram só regras de dia de evento (reserva, vaga, fila, como chegar,
-- autógrafos), e as de pós-evento (gravações, certificados) estavam em 3, fora do bloco. No teste de
-- 24/09 o agente mandou quem ficou com o fone "voltar ao Foyer de Tradução" e respondeu "não sei"
-- sobre o certificado.
--
--   * novas, prioridade 0: o evento acabou; o canal humano pós-evento;
--   * gravações e certificados sobem para 1;
--   * as de dia de evento descem para 3: continuam no banco e na busca, só saem do bloco fixo.
--
-- Reversível: voltar as prioridades listadas abaixo e desativar as duas regras novas.

insert into summit_2026.event_rules (chave, titulo, texto, aplica_em, prioridade, ativo, event_id)
select v.chave, v.titulo, v.texto, v.aplica_em, 0, true, e.id
  from summit_2026.events e,
       (values
         ('evento-encerrado',
          'O Mind Summit 2026 já aconteceu',
          'O Mind Summit 2026 aconteceu em 16 e 17/09/2026 e terminou. Não oriente como se o evento estivesse acontecendo (entrada, credenciamento, reserva de sessão, retirada ou devolução de fone no local, fila). As dúvidas de agora são de pós-evento: gravações, certificados, fotos, materiais e pendências. O Summit 2026 não está à venda.',
          array['pos_evento','suporte','concierge']),
         ('suporte-humano-pos-evento',
          'Atendimento humano pós-evento',
          'Quando a pessoa precisar de uma pessoa da equipe para resolver algo que você não resolve (documento retido ou fone não devolvido, problema com ingresso, certificado ou gravação que não chegou no prazo, reclamação), indique o WhatsApp do atendimento pós-evento: (11) 91782-0772.',
          array['pos_evento','suporte','handoff'])
       ) as v(chave, titulo, texto, aplica_em)
 where e.slug = 'mind-summit-2026'
   and not exists (select 1 from summit_2026.event_rules r where r.chave = v.chave and r.event_id = e.id);

update summit_2026.event_rules r
   set prioridade = 1, atualizado_em = now()
  from summit_2026.events e
 where e.id = r.event_id and e.slug = 'mind-summit-2026'
   and r.chave in ('gravacoes', 'certificados') and r.prioridade <> 1;

update summit_2026.event_rules r
   set prioridade = 3, atualizado_em = now()
  from summit_2026.events e
 where e.id = r.event_id and e.slug = 'mind-summit-2026'
   and r.chave in ('reserva-workshops-masterclasses', 'vagas_limitadas', 'concierge-oferece-mostrar-como-agendar',
                   'reserva_expira', 'como-chegar', 'fila_de_espera', 'livros-autografos')
   and r.prioridade < 3;
