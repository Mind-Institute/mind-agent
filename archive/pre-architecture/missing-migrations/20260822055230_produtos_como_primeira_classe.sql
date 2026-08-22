-- O Mind Summit 2026 e um PRODUTO, nao o universo (Adriana, 2026-08-22).
-- Ele vai acabar em setembro e a conversa vai virar para Institute, Journey,
-- Dash e a proxima edicao. Se o produto nao for coluna desde agora, o dia
-- da virada vira refatoracao geral — e provavelmente vira o agente falando
-- de evento morto.
--
-- Escopo: produto_codigo entra em tudo que e CONTEUDO ou OFERTA. Onde a
-- coluna fica NULL, o significado e "vale para qualquer produto" (tom de
-- voz, politica de privacidade, LGPD). Onde ela esta preenchida, o agente
-- so usa se estiver falando daquele produto.

create table if not exists mind.produtos (
  codigo text primary key,
  nome text not null,
  tipo text not null default 'evento'
    check (tipo in ('evento','formacao','assinatura','conteudo','outro')),
  linha text check (linha in ('summit','institute','dash','outro')),
  descricao_curta text,
  vende boolean not null default true,
  ativo boolean not null default true,
  comeca_em date,
  encerra_em date,
  atualizado_em timestamptz not null default now()
);

comment on table mind.produtos is
  'Cada coisa que o Mind vende ou sobre a qual os agentes conversam. vende=false: ainda pode responder, mas nao vende. ativo=false: sai do contexto dos agentes.';
comment on column mind.produtos.linha is
  'Marca/familia. Casa com mind.origens.site, que decide o utm_source.';

insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, comeca_em, encerra_em)
values ('mind-summit-2026', 'Mind Summit 2026', 'evento', 'summit',
        'Maior evento da America Latina sobre bem-estar no trabalho, lideranca e alta performance. 16 e 17 de setembro de 2026, Sao Paulo Expo.',
        '2026-09-16', '2026-09-17')
on conflict (codigo) do nothing;

alter table mind.events add column if not exists produto_codigo text references mind.produtos(codigo);
update mind.events set produto_codigo = 'mind-summit-2026' where slug = 'mind-summit-2026';

-- Conteudo e oferta passam a saber de que produto falam.
alter table mind.knowledge_documents add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.materiais           add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.origens             add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.commercial_rules    add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.policies            add column if not exists produto_codigo text references mind.produtos(codigo);
alter table treble.prompts           add column if not exists produto_codigo text references mind.produtos(codigo);
alter table treble.conversations     add column if not exists produto_codigo text references mind.produtos(codigo);

comment on column mind.knowledge_documents.produto_codigo is
  'NULL = vale para qualquer produto. Preenchido = so entra no contexto quando o agente estiver falando desse produto.';

-- Backfill: tudo que existe hoje e do Summit 2026, MENOS o que e atemporal.
update mind.knowledge_documents set produto_codigo = 'mind-summit-2026'
 where produto_codigo is null and tipo_conteudo <> 'politica';
update mind.materiais         set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
update mind.origens           set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
update mind.commercial_rules  set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
update treble.conversations   set produto_codigo = 'mind-summit-2026' where produto_codigo is null;

-- Politicas e tom de voz sao da empresa, nao do produto: ficam NULL de proposito.
-- Playbooks tambem: vender e vender, muda o que se vende.

-- Qual produto o bot assume quando a conversa nao diz outra coisa.
insert into treble.config (chave, valor) values ('produto_padrao', 'mind-summit-2026')
on conflict (chave) do update set valor = excluded.valor;

create index if not exists knowledge_documents_produto_idx on mind.knowledge_documents (produto_codigo) where ativo;
create index if not exists materiais_produto_idx on mind.materiais (produto_codigo) where ativo;
