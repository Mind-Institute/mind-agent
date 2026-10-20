-- A PÁGINA OFICIAL DO INSTITUTE PASSA A APONTAR PARA O BOTÃO DE INSCRIÇÃO.
--
-- `mind_kit_institute_catalogo` lê `intelligence.config.institute_catalogo_links`,
-- chave `paginas`, e entrega esse valor como `programas[].pagina_oficial`. Hoje são
-- URLs sem fragmento: a pessoa cai no topo de uma página longa e precisa rolar até o
-- botão. Quatro dos seis programas compartilham a MESMA página
-- (`/certificacao-avancada`), porque, como diz o próprio `como_comprar` do catálogo,
-- "as formações avulsas são contratadas na página da Certificação Avançada,
-- escolhendo a formação" — então, para elas, cair no topo é cair no lugar errado
-- duas vezes.
--
-- Decisão de 20/10/2026: mandar a página com a âncora, para a pessoa já chegar no
-- ponto de inscrição.
--
-- AS ÂNCORAS NÃO FORAM INVENTADAS. Foram lidas das páginas publicadas em
-- 20/10/2026 (HTTP 200, `id=` no HTML servido):
--
--   joinmind.com.br/certificacao-avancada
--       #inscricao  secção "Certificação Avançada em Liderança Positiva · Entre no
--                   Mind Institute" — o fechamento com o botão
--       #avulsas    secção "Formações avulsas · Escolha sua formação"
--   joinmind.com.br/gestao-estrategica-bem-estar
--       #inscricao  secção de fechamento
--   joinmind.com.br/programa/mind-journey
--       #inscricao  secção "Mind Journey 2026–2027"
--
-- Por isso o destino depende do que a pessoa está comprando, e não só da página:
--   certificação e especialização -> #inscricao (compra o percurso inteiro)
--   formação avulsa               -> #avulsas   (precisa escolher qual formação)
--   journey                       -> #inscricao
--
-- O runtime do WhatsApp valida o link por IGUALDADE EXATA contra o que o Kit mandou,
-- fragmento incluído, então o modelo não consegue trocar nem inventar âncora. Mudar
-- aqui muda nos dois canais que leem este catálogo (WhatsApp e App), que é o
-- comportamento desejado: é o mesmo catálogo oficial.
--
-- Se uma âncora sumir da página, o link continua válido — o navegador ignora
-- fragmento desconhecido e abre o topo, que é exatamente o comportamento de hoje.
-- Nenhum caminho fica pior do que estava.

update intelligence.config
   set valor = jsonb_set(
         valor::jsonb,
         '{paginas}',
         jsonb_build_object(
           'certificacao-lideranca-positiva',
             'https://joinmind.com.br/certificacao-avancada#inscricao',
           'certificacao-gestao-estrategica-bem-estar',
             'https://joinmind.com.br/gestao-estrategica-bem-estar#inscricao',
           'mind-journey',
             'https://joinmind.com.br/programa/mind-journey#inscricao',
           'lideranca-consciente',
             'https://joinmind.com.br/certificacao-avancada#avulsas',
           'significado-e-proposito-no-trabalho',
             'https://joinmind.com.br/certificacao-avancada#avulsas',
           'seguranca-psicologica-aplicada-a-inovacao',
             'https://joinmind.com.br/certificacao-avancada#avulsas'
         )
       )::text
 where chave = 'institute_catalogo_links';

-- Confere que os seis programas do catálogo saíram com fragmento. Falha a migration
-- se algum ficou sem — melhor não aplicar do que aplicar pela metade.
do $$
declare
  v_sem_ancora int;
begin
  select count(*)
    into v_sem_ancora
    from jsonb_each_text(
           (select valor::jsonb -> 'paginas'
              from intelligence.config
             where chave = 'institute_catalogo_links')) as p(codigo, url)
   where position('#' in url) = 0;

  if v_sem_ancora > 0 then
    raise exception 'institute_catalogo_links: % página(s) sem âncora', v_sem_ancora;
  end if;
end $$;
