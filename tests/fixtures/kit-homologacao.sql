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
-- A conversa usada é apenas um ancoradouro para o Kit resolver contexto, e nada é
-- escrito.
--
-- ATENÇÃO — `customer_intelligence` NÃO PODE IR PARA A FIXTURE.
--
-- Ele é o único bloco por PESSOA: traz cargo, ICP, empresa e o histórico de
-- interesses com data, de um indivíduo identificável. A primeira versão desta
-- fixture o incluiu por descuido, e com ele foram para o repositório o cargo
-- ("Gerente de CRM"), o ICP e cinco interesses datados de uma pessoa real —
-- inclusive um pedido de descadastramento.
--
-- Por isso o `- 'customer_intelligence'` abaixo: o bloco é removido na origem, e a
-- bateria usa no lugar um perfil SINTÉTICO, escrito à mão em
-- `kit-homologacao.json`, com a mesma forma e nenhuma pessoa dentro. O perfil
-- sintético preserva de propósito um interesse lembrado em Summit, porque é
-- exatamente isso que a homologação precisa exercitar.
--
-- Ao regenerar: confira que o bloco continua fora e reponha o sintético.

-- Os demais blocos (catálogo, inteligência de produto) são informação de produto,
-- não ficha de pessoa, e podem ser versionados.

with c as (
  select id from engagement.conversas
  where canal = 'whatsapp' and agente = 'treble-inbound-agent'
  order by iniciada_em desc
  limit 1
)
select jsonb_pretty(jsonb_build_object(
  'gerado_em',   now()::text,
  'fonte',       'mind_agent_kit(rota, conversa, {}) no projeto ymnmotgglsrxmjmonwjz',
  -- `#-` remove o bloco por pessoa ANTES de ele sair do banco.
  'institute',   public.mind_agent_kit('institute', (select id from c), '{}'::jsonb)
                   #- '{structured,customer_intelligence}',
  'dash',        public.mind_agent_kit('dash',      (select id from c), '{}'::jsonb)
                   #- '{structured,customer_intelligence}',
  'canal_rotas', public.mind_canal_rotas('whatsapp'),
  'gate', jsonb_build_object(
     'institute',       public.mind_rota_capacidade('institute','whatsapp'),
     'dash',            public.mind_rota_capacidade('dash','whatsapp'),
     'cliente_suporte', public.mind_rota_capacidade('cliente_suporte','whatsapp'),
     'summit_b2c',      public.mind_rota_capacidade('summit_b2c','whatsapp'),
     'summit_b2b',      public.mind_rota_capacidade('summit_b2b','whatsapp'))
));
