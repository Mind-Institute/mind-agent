-- Rotas depois do Summit 2026. Decisão da Adriana em 24/09/2026:
--   * App: desligar `summit_b2c`. Ficam concierge (pós-evento), suporte, Institute e Dash.
--   * WhatsApp: desligar as duas rotas de venda do Summit e deixar o suporte; ligar Institute
--     e Dash.
--
-- O Summit já saiu de venda no catálogo (20260924190643). Com a rota de venda ligada, o
-- Router ainda mandava gente para um vendedor sem produto: 3 respostas no app desde 18/09.
--
-- Efeito no WhatsApp: `treble-inbound-agent` só EXECUTA `summit_b2c`/`summit_b2b`; qualquer
-- outra rota passa pelo Gate e encerra o turno com transferência para humano. Com esta
-- mudança, Institute e Dash viram rotas reconhecíveis que chegam ao time com a necessidade
-- identificada; o agente não responde sobre eles no WhatsApp até o runtime da lane #40
-- aprender a executá-las. O Gate responde `canal_incompativel` para as rotas desligadas,
-- então a rota comercial rápida do runtime também cai em transferência, não em venda.
--
-- Reversível: inverter os `ativo` abaixo. Idempotente.

update agentes.canal_competencia
   set ativo = false, atualizado_em = now(),
       observacao = 'Desligada em 24/09/2026: Summit 2026 encerrado e fora de venda.'
 where (canal, rota) in (('mindagent-web','summit_b2c'), ('whatsapp','summit_b2c'), ('whatsapp','summit_b2b'))
   and ativo;

update agentes.canal_competencia
   set ativo = true, atualizado_em = now(),
       observacao = 'Ligada em 24/09/2026 (Adriana): Institute/Dash reconhecidos no WhatsApp; '
                 || 'o runtime do Treble ainda não executa, então transfere ao time com a necessidade.'
 where (canal, rota) in (('whatsapp','institute'), ('whatsapp','dash'))
   and not ativo;
