-- A curadoria conservadora nao deve colapsar jobs canonicamente distintos.
-- Cada JTBD continua exigindo evidencia direta propria na fala do lead.

update agentes.prompts
set conteudo = replace(
      conteudo,
      E'- múltiplos JTBDs especulativos para explicar uma única fala. Emita somente jobs diretamente sustentados.\n',
      E'- múltiplos JTBDs especulativos para explicar uma única fala. Emita somente jobs diretamente sustentados.\n'
      || E'- não colapse JTBDs canonicamente distintos quando a mesma fala sustenta diretamente mais de um progresso. Cada job emitido precisa ter seu próprio `evidence_quote`; a coincidência na mesma mensagem não reduz dois jobs a um.\n'
    ),
    versao = greatest(versao, 6),
    atualizado_em = now()
where chave = 'analise_concierge'
  and ativo
  and position('não colapse JTBDs canonicamente distintos' in conteudo) = 0;

update agentes.prompts
set conteudo = replace(
      conteudo,
      E'- "Sou HRBP e preciso desenvolver os gestores que apoio" → `role`, ICP inequívoco e JT04.\n',
      E'- "Sou HRBP e preciso desenvolver os gestores que apoio" → `role`, ICP inequívoco e JT04.\n'
      || E'- "Sou HRBP; preciso desenvolver os gestores que apoio e eles evitam conversas difíceis" → JT04 e JT05, porque a fala sustenta dois progressos distintos.\n'
    ),
    versao = greatest(versao, 6),
    atualizado_em = now()
where chave = 'analise_concierge'
  and ativo
  and position('porque a fala sustenta dois progressos distintos' in conteudo) = 0;

do $contract$
declare c text; v integer;
begin
  select conteudo, versao into c, v
  from agentes.prompts where chave='analise_concierge' and ativo;
  if v < 6 then raise exception 'prompt nao avancou para v6'; end if;
  if position('não colapse JTBDs canonicamente distintos' in c)=0 then raise exception 'regra de jobs distintos ausente'; end if;
  if position('porque a fala sustenta dois progressos distintos' in c)=0 then raise exception 'exemplo JT04/JT05 ausente'; end if;
end
$contract$;
