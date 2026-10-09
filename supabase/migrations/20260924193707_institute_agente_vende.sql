-- O agente do Institute passa a VENDER com o catálogo real.
--
-- Decisões da Adriana em 24/09/2026: "o agente pode informar o preço"; "o ideal seria que ele
-- conseguisse vender o institute, inclusive que ele tenha as infos do site do institute ... e que
-- também está no schema institute e catálogo e ofertas"; "nomes dos cursos estão errados porque
-- ele não está vendo o nome certo".
--
-- O que o agente do Institute recebia até aqui (medido em 24/09 no Kit da rota):
--   * `playbook_institute` §4: "não invente preço, turma, calendário ... Não prometa contato";
--   * `vendas_institute` (Vinicius, 17/09): preços e datas como retrato e "consulte as views
--     `api`" — mas a rota não tem ferramenta para consultar nada;
--   * `product_intelligence`: nomes antigos escritos à mão ("Formação em Gestão Estratégica de
--     Saúde Mental...", "Certificação Avançada em Liderança e Saúde Mental Positiva"), sem
--     Liderança Consciente nem Mind Journey, e `nao_contem: [preço, turma, ...]`.
-- Resultado: "O JSON oficial que você enviou diz que não contém preço" para um lead quente, com
-- a condição Summit vigente até 30/09.
--
-- Menor mudança, nas casas que já existem:
--   1. `intelligence.config.institute_catalogo_links`: página oficial de cada programa no site
--      (joinmind.com.br, lido em 24/09) e o WhatsApp do time do Institute publicado no site;
--   2. `mind_kit_institute_catalogo`: bloco `structured` lido ao vivo das views `api` —
--      programas com nome oficial, ofertas vigentes (sem order bump, que ninguém executa),
--      preço à vista e parcelado, prazo da condição, bônus, encontros, formadoras, o que a
--      Certificação inclui, FAQ com marcadores resolvidos (entrada com marcador que o banco não
--      resolve é omitida) e condições;
--   3. a rota `institute` carrega o bloco (opcional: se falhar, o turno segue sem ele);
--   4. `product_intelligence`: os nomes dos programas do Institute passam a ser os do catálogo, e
--      o bloco avisa que preço e turma do Institute estão em `institute_catalogo`;
--   5. `playbook_institute` §4 troca "não fale de preço / não prometa contato" por venda com o
--      catálogo; `vendas_institute` §1 aponta para o bloco em vez das views que o agente não lê.
--
-- Reversível: desativar o bloco em `agentes.kit_blocos` e restaurar as versões anteriores dos dois
-- prompts (versão atual - 1, no histórico de `agentes.prompts`/migrations).

-- 1. Links oficiais ----------------------------------------------------------------------------
insert into intelligence.config (chave, valor) values ('institute_catalogo_links', $cfg$
{
  "paginas": {
    "certificacao-lideranca-positiva": "https://joinmind.com.br/certificacao-avancada",
    "certificacao-gestao-estrategica-bem-estar": "https://joinmind.com.br/gestao-estrategica-bem-estar",
    "mind-journey": "https://joinmind.com.br/programa/mind-journey",
    "lideranca-consciente": "https://joinmind.com.br/certificacao-avancada",
    "significado-e-proposito-no-trabalho": "https://joinmind.com.br/certificacao-avancada",
    "seguranca-psicologica-aplicada-a-inovacao": "https://joinmind.com.br/certificacao-avancada"
  },
  "conteudo_programatico": {
    "certificacao-gestao-estrategica-bem-estar": "https://joinmind.com.br/conteudo-programatico/certificacao-gestao-estrategica-bem-estar",
    "lideranca-consciente": "https://joinmind.com.br/conteudo-programatico/lideranca-consciente",
    "significado-e-proposito-no-trabalho": "https://joinmind.com.br/conteudo-programatico/significado-e-proposito-no-trabalho",
    "seguranca-psicologica-aplicada-a-inovacao": "https://joinmind.com.br/conteudo-programatico/seguranca-psicologica-aplicada-a-inovacao"
  },
  "como_comprar": "Na página oficial do programa, o botão de inscrição leva ao pagamento seguro. As formações avulsas são contratadas na página da Certificação Avançada, escolhendo a formação.",
  "contato": {
    "time_institute_whatsapp": "(11) 93020-7733",
    "time_institute_link": "https://wa.me/5511930207733"
  }
}
$cfg$)
on conflict (chave) do update set valor = excluded.valor;

-- 2. Bloco do catálogo --------------------------------------------------------------------------
create or replace function public.mind_kit_institute_catalogo(p_conversa_id uuid, p_necessidade jsonb)
returns jsonb
language sql
stable
security definer
set search_path to ''
as $fn$
  with cfg as (
    select coalesce((select c.valor::jsonb from intelligence.config c where c.chave = 'institute_catalogo_links'),
                    '{}'::jsonb) v
  ),
  ofertas as (
    select o.*,
           case when o.encerra_em is null then 'preço regular (sem prazo)' else 'condição com prazo' end as faixa,
           'R$ ' || replace(to_char(o.valor, 'FM999,999,990'), ',', '.') as a_vista,
           case when o.parcelas > 1
                then o.parcelas || 'x de R$ ' || replace(to_char(o.valor_parcela, 'FM999,999,990'), ',', '.') end as parcelado
      from api.ofertas o
     where o.vigente
       and coalesce(o.elegibilidade->>'tipo', '') <> 'order_bump'
  ),
  por_programa as (
    select distinct on (o.programa_codigo) o.programa_codigo, o.a_vista, o.parcelado
      from ofertas o order by o.programa_codigo, o.valor
  ),
  avulsa as (
    select o.a_vista || coalesce(' (ou ' || o.parcelado || ')', '') as texto
      from ofertas o join api.programas p on p.codigo = o.programa_codigo
     where p.tipo = 'formacao' order by o.valor limit 1
  ),
  prazo as (
    select to_char(min(o.encerra_em) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY "às" HH24"h"MI') as texto
      from ofertas o where o.encerra_em > now()
  ),
  primeiro as (
    select e.programa_codigo,
           to_char(min(e.acontece_em) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY "às" HH24"h"MI') as texto
      from api.encontros e group by e.programa_codigo
  ),
  faq as (
    select f.escopo, f.ordem, f.pergunta,
           replace(replace(replace(replace(replace(f.resposta,
             '%%PRECO_AVULSA%%', coalesce((select texto from avulsa), '%%PRECO_AVULSA%%')),
             '%%PRECO_COMPLETO%%', coalesce((select pp.a_vista from por_programa pp where pp.programa_codigo = f.escopo), '%%PRECO_COMPLETO%%')),
             '%%PARCELAMENTO%%', coalesce((select pp.parcelado from por_programa pp where pp.programa_codigo = f.escopo), '%%PARCELAMENTO%%')),
             '%%PRAZO%%', coalesce((select texto from prazo), '%%PRAZO%%')),
             '%%PRIMEIRO_ENCONTRO%%', coalesce((select pr.texto from primeiro pr where pr.programa_codigo = f.escopo), '%%PRIMEIRO_ENCONTRO%%'))
           as resposta
      from api.faq f
  )
  select jsonb_build_object(
    'bloco', 'institute_catalogo',
    'fonte', 'Catálogo oficial do Mind Institute, lido do banco agora. Nomes, preços, prazos, datas e links daqui valem mais que qualquer outro texto.',
    'agora', to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    'como_comprar', (select v->>'como_comprar' from cfg),
    'contato_time_institute', (select v->'contato' from cfg),
    'programas', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'codigo', p.codigo,
        'nome', p.nome,
        'tipo', p.tipo,
        'subtitulo', p.subtitulo,
        'descricao', p.descricao,
        'carga_horaria_h', p.carga_horaria_h,
        'duracao_semanas', p.duracao_semanas,
        'duracao_meses', p.duracao_meses,
        'modalidade', p.modalidade,
        'inicio', to_char(p.inicia_em, 'DD/MM/YYYY') || case when p.inicio_previsto then ' (data prevista, não confirmada)' else '' end,
        'fim', to_char(p.encerra_em, 'DD/MM/YYYY'),
        'pagina_oficial', (select v->'paginas'->>p.codigo from cfg),
        'conteudo_programatico', (select v->'conteudo_programatico'->>p.codigo from cfg),
        'formadoras', (
          select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                   'nome', x.nome, 'papel', x.papel, 'cargo', x.cargo, 'nota', x.nota)) order by x.ordem)
            from api.programa_pessoas x where x.programa_codigo = p.codigo),
        'encontros_ao_vivo', (
          select jsonb_agg(to_char(e.acontece_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24"h"MI')
                           || coalesce(' · ' || e.tema, '') order by e.ordem)
            from api.encontros e where e.programa_codigo = p.codigo),
        'ofertas', (
          select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                   'nome', o.nome,
                   'faixa', o.faixa,
                   'a_vista', o.a_vista,
                   'parcelado', o.parcelado,
                   'valida_ate', to_char(o.encerra_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY "às" HH24"h"MI'),
                   'inclui', (select jsonb_agg(pp.nome order by pp.ordem)
                                from api.oferta_inclui oi join api.programas pp on pp.codigo = oi.programa_codigo
                               where oi.oferta_codigo = o.codigo and oi.programa_codigo <> p.codigo),
                   'bonus', (select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                                      'nome', b->>'nome', 'descricao', b->>'descricao', 'detalhe', b->>'detalhe',
                                      'valor_de_referencia', 'R$ ' || replace(to_char((b->>'valor_referencia')::numeric, 'FM999,999,990'), ',', '.'))))
                               from jsonb_array_elements(coalesce(o.bonus, '[]'::jsonb)) b
                              where coalesce((b->>'vigente')::boolean, true)))) order by o.valor)
            from ofertas o where o.programa_codigo = p.codigo),
        'faq', (
          select jsonb_agg(jsonb_build_object('pergunta', f.pergunta, 'resposta', f.resposta) order by f.ordem)
            from faq f where f.escopo = p.codigo and f.resposta not like '%\%\%%')
      )) order by p.ordem)
      from api.programas p), '[]'::jsonb),
    'condicoes', coalesce((
      select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('titulo', c.titulo, 'texto', c.texto)) order by c.prioridade)
        from api.condicoes c), '[]'::jsonb)
  );
$fn$;

comment on function public.mind_kit_institute_catalogo(uuid, jsonb) is
  'Bloco structured da rota institute: catálogo oficial ao vivo (programas, ofertas vigentes sem order bump, bônus, encontros, formadoras, FAQ com marcadores resolvidos, condições, páginas oficiais e WhatsApp do time). O que cada oferta inclui fica na oferta, porque só a condição traz o Journey. Sem LLM, sem escrita.';
revoke all on function public.mind_kit_institute_catalogo(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.mind_kit_institute_catalogo(uuid, jsonb) to service_role;

-- 3. A rota institute carrega o bloco -----------------------------------------------------------
insert into agentes.kit_blocos (rota, bloco, provider, secao, obrigatorio, ativo)
values ('institute', 'institute_catalogo', 'public.mind_kit_institute_catalogo', 'structured', false, true)
on conflict (rota, bloco) do update
   set provider = excluded.provider, secao = excluded.secao, obrigatorio = excluded.obrigatorio, ativo = excluded.ativo;

-- 4. Nomes dos programas no product_intelligence ------------------------------------------------
update institute.knowledge_documents d
   set metadata = jsonb_set(d.metadata, '{programas}', (
         select jsonb_agg(case p->>'codigo'
                  when 'gestao_estrategica_bem_estar'
                    then p || '{"nome_oficial":"Especialização em Gestão Estratégica de Bem-Estar no Trabalho"}'
                  when 'seguranca_psicologica'
                    then p || '{"nome_oficial":"Segurança Psicológica Aplicada a Resultados e Inovação"}'
                  when 'engajamento_significado'
                    then p || '{"nome_oficial":"Engajamento e Significado no Trabalho"}'
                  when 'certificacao_avancada'
                    then p || '{"nome_oficial":"Certificação Avançada em Liderança Positiva"}'
                  else p end)
           from jsonb_array_elements(d.metadata->'programas') p))
 where d.id = md5('mind-product-intelligence:mind-institute')::uuid
   and d.metadata ? 'programas';

do $migra$
declare d text; o text;
begin
  d := pg_get_functiondef('public.mind_kit_product_intelligence(uuid,jsonb)'::regprocedure);
  o := d;
  d := replace(d,
    $x$'nao_contem',jsonb_build_array('preço','lote','parcelamento','checkout','turma','disponibilidade'))$x$,
    $x$'nao_contem',jsonb_build_array('preço','lote','parcelamento','checkout','turma','disponibilidade'),
    'observacao','Este bloco é posicionamento. Preço, turma, datas e nomes oficiais do Mind Institute estão no bloco institute_catalogo quando ele vier no contexto.')$x$);
  if d = o and position('institute_catalogo' in d) = 0 then
    raise exception 'product_intelligence: trecho nao_contem não encontrado';
  end if;
  execute d;
end $migra$;

-- 5. Prompts ------------------------------------------------------------------------------------
do $migra$
declare c text; o text; i int; j int;
begin
  -- playbook_institute §4
  select conteudo into c from agentes.prompts where chave = 'playbook_institute';
  o := c;
  i := position('4. VERDADE OPERACIONAL E COMERCIAL' in c);
  j := position('5. LIMITES' in c);
  if i > 0 and j > i then
    c := left(c, i - 1) || $txt$4. VENDA DO INSTITUTE (decisão da Adriana, 24/09/2026)
- Você vende o Mind Institute. O bloco `institute_catalogo` é o catálogo oficial, lido do banco a cada mensagem: nomes oficiais, preço à vista e parcelado, prazo da condição, bônus, datas dos encontros, formadoras, FAQ, condições e a página oficial de cada programa. Use exatamente os nomes, valores, prazos e links de lá.
- Quando houver fit, recomende o programa pelo nome oficial, diga o preço vigente (à vista e parcelado) e, se a oferta tiver prazo, até quando vale. Mande a página oficial para a pessoa se inscrever.
- Se a pessoa está decidindo, facilite: responda a dúvida ou objeção com os dados do catálogo e mande o link. Fale do programa que faz sentido; não despeje o catálogo inteiro.
- O que não estiver no catálogo (preço corporativo, cupom, nota fiscal, condição especial, matrícula já feita) não se inventa: passe o WhatsApp do time do Institute que está no catálogo.
- Se a pessoa quiser falar com alguém, passe o WhatsApp do time do Institute. Se ela deixar o próprio WhatsApp, registre em `whatsapp_informado`, mas não diga que o time vai ligar: diga que ela pode chamar o time no WhatsApp.
- Nunca fale de estrutura interna (JSON, bloco, banco, contexto, dados enviados).

$txt$ || substr(c, j);
  end if;
  if c = o and position('4. VENDA DO INSTITUTE' in c) = 0 then
    raise exception 'playbook_institute: seção 4 não encontrada';
  end if;
  if c <> o then
    update agentes.prompts set conteudo = c, versao = versao + 1, atualizado_em = now()
     where chave = 'playbook_institute';
  end if;

  -- vendas_institute §1
  select conteudo into c from agentes.prompts where chave = 'vendas_institute';
  o := c;
  i := position('Preço, parcela, data de turma, prazo de oferta e valor de bônus NÃO estão aqui' in c);
  j := position('Se este documento e o banco discordarem, O BANCO ESTÁ CERTO.' in c);
  if i > 0 and j > i then
    c := left(c, i - 1) || $txt$Preço, parcela, data de turma, prazo de oferta e valor de bônus NÃO estão aqui
como verdade: os números abaixo são um retrato de 17/09. A verdade está no bloco
`institute_catalogo` do contexto, lido do banco a cada mensagem (programas,
ofertas vigentes, bônus, encontros, formadoras, FAQ, condições e páginas).

Se este documento e o bloco `institute_catalogo` discordarem, O BLOCO ESTÁ CERTO.$txt$
         || substr(c, j + length('Se este documento e o banco discordarem, O BANCO ESTÁ CERTO.'));
  end if;
  if c = o and position('O BLOCO ESTÁ CERTO' in c) = 0 then
    raise exception 'vendas_institute: seção 1 não encontrada';
  end if;
  if c <> o then
    update agentes.prompts set conteudo = c, versao = versao + 1, atualizado_em = now()
     where chave = 'vendas_institute';
  end if;
end $migra$;
