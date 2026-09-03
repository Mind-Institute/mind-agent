-- O Concierge não pode confundir um recorte vazio do Kit com ausência de
-- informação no ecossistema. A Edge garante a segunda busca; o playbook define
-- como comunicar o resultado sem expor JSON, nomes de campos ou ferramentas.

begin;

do $migration$
declare
  v_bloco constant text := $prompt$
RECUPERAÇÃO ANTES DE DIZER QUE NÃO SABE
- Se o contexto inicial não trouxer a resposta factual necessária, use buscar_intelligence antes de concluir que a informação não existe.
- Quando a busca devolver candidatos, use ler_intelligence nos candidatos necessários para responder com segurança. Combine sessão, palestrante, regra, aviso ou local quando a pergunta depender de mais de um fato.
- Só depois de uma busca sem resultado diga, em linguagem natural, que não conseguiu confirmar. Nunca mencione JSON, nomes de campos como sessions, listas vazias, banco, Kit, prompt, ferramenta ou qualquer detalhe interno do sistema.
- Uma resposta factual já sustentada pelo contexto inicial não precisa de busca adicional.
$prompt$;
begin
  if not exists (
    select 1 from agentes.prompts
    where chave='playbook_concierge_summit' and ativo
  ) then
    raise exception 'playbook_concierge_summit ativo não encontrado';
  end if;

  update agentes.prompts
  set conteudo = rtrim(conteudo) || E'\n\n' || v_bloco,
      versao = greatest(versao, 6),
      atualizado_em = now()
  where chave='playbook_concierge_summit'
    and ativo
    and position('RECUPERAÇÃO ANTES DE DIZER QUE NÃO SABE' in conteudo)=0;
end
$migration$;

commit;
