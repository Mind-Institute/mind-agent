-- Uma fonte por fato, passo 1 (Adriana aprovou apagar as duplicacoes).
--
-- Quatro regras de mind.event_rules eram copia byte a byte de um
-- knowledge_document (comparado ignorando espaco e caixa). Duas copias do
-- mesmo fato e uma que desatualiza sozinha.
--
-- Quem vence: mind.knowledge_documents. E de la que os agentes leem — o
-- Treble monta 'faq' e 'conteudo_aprovado' dali, e o concierge usa os
-- chunks. mind.event_rules nao e lida por nenhuma funcao do banco alem da
-- de gravacao do admin, e nao aparece em lugar nenhum do repositorio.
--
-- Texto das quatro, para o caso de precisar voltar (o mesmo texto continua
-- vivo no documento de titulo correspondente):
--   assentos-arena-mind  -> "Tem assento marcado?"
--   diferenca-mind-vip   -> "Qual a diferenca entre Mind e VIP?"
--   masterclasses-prime  -> "O que sao as Masterclasses Prime?"
--   traducao-simultanea  -> "Havera traducao simultanea?"
--
-- NAO sao duplicatas e ficam: como-chegar, fila_de_espera, gravacoes,
-- reserva_expira, reserva-workshops-masterclasses, sessoes-remotas,
-- vagas_limitadas.

delete from mind.event_rules r
 where exists (
   select 1 from mind.knowledge_documents k
    where regexp_replace(lower(trim(k.corpo)), '\s+', ' ', 'g')
        = regexp_replace(lower(trim(r.texto)), '\s+', ' ', 'g'));
