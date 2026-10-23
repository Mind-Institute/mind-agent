-- Router: o Summit 2026 acabou. No teste de 24/09, "Como obtenho o certificado?" foi para
-- `institute` e voltou explicando a credencial dos cursos, não o certificado do Summit — que
-- existe como regra oficial (a partir de 30 dias, no e-mail do ingresso). Na semana do evento a
-- mesma pergunta ia para o concierge. Uma seção curta dá ao Router o momento do ecossistema.
-- Reversível: remover o bloco "PÓS-SUMMIT 2026" de `router_universal`.

do $migra$
declare c text; o text; marca text := $m$==================================================
SUMMIT_B2B$m$;
begin
  select conteudo into c from agentes.prompts where chave = 'router_universal';
  if position('PÓS-SUMMIT 2026' in c) > 0 then return; end if;
  o := c;
  c := replace(c, marca, $txt$==================================================
PÓS-SUMMIT 2026
==================================================

O Mind Summit 2026 aconteceu em 16 e 17/09/2026 e não está à venda.

Pergunta sobre certificado, gravação, foto, material ou pendência do Summit, sem citar um curso,
formação ou certificação do Institute, é do Summit:
- informação (como obter, quando sai, onde assistir) → concierge_summit;
- problema (não recebeu no prazo, documento retido, erro) → cliente_suporte.

"Como obtenho o certificado?" → concierge_summit.
"Como recebo a credencial da Certificação Avançada?" → institute.


$txt$ || marca);
  if c = o then raise exception 'router_universal: seção SUMMIT_B2B não encontrada'; end if;
  update agentes.prompts set conteudo = c, versao = versao + 1, atualizado_em = now()
   where chave = 'router_universal';
end $migra$;
