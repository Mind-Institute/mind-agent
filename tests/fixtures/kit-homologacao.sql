-- Regenera `tests/fixtures/kit-homologacao.json`.
--
-- A fixture é uma CÓPIA CONGELADA do Kit vivo: playbook montado, blocos structured,
-- política do canal e estado do Gate. A bateria de homologação roda contra ela para
-- que a revisão seja reproduzível — duas leituras da mesma conversa precisam ter
-- lido o mesmo catálogo.
--
-- REGENERE sempre que mudar playbook, catálogo, preço, bloco de Kit ou política de
-- canal. Em especial: a migration `20261020151000` acrescenta a âncora `#inscricao`
-- às páginas do Institute — depois de aplicá-la, esta fixture está velha.
--
-- Como rodar (somente leitura; `mind_agent_kit` e `mind_kit_*` são STABLE):
--
--   psql "$DATABASE_URL" -At -f tests/fixtures/kit-homologacao.sql \
--     | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>
--         require("fs").writeFileSync("tests/fixtures/kit-homologacao.json",
--           JSON.stringify(JSON.parse(s),null,2)))'
--
-- A conversa usada é apenas um ancoradouro para o Kit resolver contexto; nada é
-- escrito, e nenhum dado pessoal entra na fixture (os blocos de Kit são catálogo e
-- inteligência de produto, não ficha de pessoa). Confira isso ao regenerar.

with c as (
  select id from engagement.conversas
  where canal = 'whatsapp' and agente = 'treble-inbound-agent'
  order by iniciada_em desc
  limit 1
)
select jsonb_pretty(jsonb_build_object(
  'gerado_em',   now()::text,
  'fonte',       'mind_agent_kit(rota, conversa, {}) no projeto ymnmotgglsrxmjmonwjz',
  'institute',   public.mind_agent_kit('institute', (select id from c), '{}'::jsonb),
  'dash',        public.mind_agent_kit('dash',      (select id from c), '{}'::jsonb),
  'canal_rotas', public.mind_canal_rotas('whatsapp'),
  'gate', jsonb_build_object(
     'institute',       public.mind_rota_capacidade('institute','whatsapp'),
     'dash',            public.mind_rota_capacidade('dash','whatsapp'),
     'cliente_suporte', public.mind_rota_capacidade('cliente_suporte','whatsapp'),
     'summit_b2c',      public.mind_rota_capacidade('summit_b2c','whatsapp'),
     'summit_b2b',      public.mind_rota_capacidade('summit_b2b','whatsapp'))
));
