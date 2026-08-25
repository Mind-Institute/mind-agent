
do $migration$
declare
  v_event_id uuid;
  v_venue_id uuid;
  v_entry_id uuid;
begin
  select id into strict v_event_id
  from mind.events
  where slug = 'mind-summit-2026';

  update mind.events
  set local = 'Pavilhão 3 · Transamérica Expo Center',
      cidade = 'São Paulo',
      atualizado_em = now()
  where id = v_event_id;

  insert into mind.venues (
    event_id, slug, nome, endereco, transporte, acessibilidade, mapa_url, ativo, atualizado_em
  )
  values (
    v_event_id,
    'transamerica-expo-center-pavilhao-3',
    'Transamérica Expo Center · Pavilhão 3',
    jsonb_build_object(
      'centro_eventos', 'Transamérica Expo Center',
      'pavilhao', '3',
      'cidade', 'São Paulo',
      'estado', 'SP',
      'pais', 'Brasil',
      'fonte', 'mapa oficial Mind Summit 2026'
    ),
    null,
    'O mapa indica elevador e escadas na lateral direita; a rota acessível ainda precisa de validação operacional.',
    null,
    true,
    now()
  )
  on conflict (event_id, slug) do update
  set nome = excluded.nome,
      endereco = excluded.endereco,
      acessibilidade = excluded.acessibilidade,
      ativo = true,
      atualizado_em = now()
  returning id into v_venue_id;

  update mind.locations
  set slug = case nome
      when 'Arena Mind' then 'arena-mind'
      when 'Arena Top Voice' then 'arena-top-voice'
      when 'Arena Sextante' then 'arena-sextante'
      when 'Livraria da Vila' then 'livraria-da-vila'
      when 'Prime Lounge' then 'lounge-prime'
      when 'Sala Masterclass' then 'sala-masterclass'
      when 'Sala Workshop 1' then 'sala-workshop-1'
      when 'Sala Workshop 2' then 'sala-workshop-2'
      when 'Sala Workshop 3' then 'sala-workshop-3'
      else slug
    end,
    venue_id = v_venue_id,
    atualizado_em = now()
  where event_id = v_event_id;

  with data (
    slug, nome, tipo, aliases, descricao, como_chegar,
    x_percent, y_percent, confianca, acessibilidade
  ) as (
    values
      (
        'arena-mind', 'Arena Mind', 'arena',
        array['palco mind','arena principal','palco principal','mind']::text[],
        'Arena principal do evento, com setores Área Prime, Área VIP e Área Mind.',
        'A Arena Mind fica na parte superior esquerda do mapa. Saindo da entrada, passe pelo credenciamento e siga pelo corredor principal; deixe a Livraria da Vila e a Arena Sextante à direita e a Praça de Alimentação à esquerda. Continue até a grande arena à esquerda. O palco fica na extremidade superior da arena.',
        31.8, 44.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'arena-top-voice', 'Arena Top Voice', 'arena',
        array['palco top voice','top voice','arena linkedin','palco linkedin']::text[],
        'Arena Top Voice, localizada no eixo direito do pavilhão.',
        'A Arena Top Voice fica na parte superior direita do mapa. A partir da entrada, siga pelo corredor lateral direito, passe pela Livraria da Vila, Arena Sextante e áreas de Coworking e Diversidade. A arena fica logo abaixo dos lounges BWG, Prime e Heineken.',
        84.0, 49.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'arena-sextante', 'Arena Sextante', 'arena',
        array['palco sextante','sextante']::text[],
        'Arena da Editora Sextante.',
        'A Arena Sextante fica na lateral direita, na metade inferior do mapa. Partindo da entrada, siga pelo corredor direito. Ela está acima da Livraria da Vila e abaixo das áreas de Coworking e Mind + Diversidade.',
        84.0, 72.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'livraria-da-vila', 'Livraria da Vila', 'ativacao',
        array['livraria','da vila','livros']::text[],
        'Livraria oficial indicada no mapa do evento.',
        'A Livraria da Vila fica na lateral direita, logo abaixo da Arena Sextante e acima do credenciamento e da entrada.',
        84.0, 79.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'lounge-prime', 'Prime Lounge', 'lounge',
        array['lounge prime','prime','área prime']::text[],
        'Lounge Prime localizado no conjunto de lounges da parte superior direita.',
        'O Prime Lounge fica na parte superior direita do mapa, entre o Lounge Heineken e o Lounge BWG, acima da Arena Top Voice.',
        84.0, 38.3, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'lounge-heineken', 'Lounge Heineken', 'lounge',
        array['heineken','lounge da heineken']::text[],
        'Lounge Heineken.',
        'O Lounge Heineken fica no topo da lateral direita, acima do Prime Lounge e da Arena Top Voice.',
        84.0, 33.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'lounge-bwg', 'Lounge BWG', 'lounge',
        array['bwg','lounge da bwg']::text[],
        'Lounge BWG.',
        'O Lounge BWG fica na lateral direita, abaixo do Prime Lounge e imediatamente acima da Arena Top Voice.',
        84.0, 43.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'area-coworking', 'Área Coworking', 'ativacao',
        array['coworking','área de coworking']::text[],
        'Área de coworking indicada no mapa.',
        'A Área Coworking fica na lateral direita, abaixo da Arena Top Voice e acima da Arena Sextante. Ela está à esquerda do espaço Mind + Diversidade.',
        78.0, 60.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'mind-diversidade', 'Mind + Diversidade', 'ativacao',
        array['diversidade','mind diversidade','espaço diversidade']::text[],
        'Espaço Mind + Diversidade.',
        'O espaço Mind + Diversidade fica na lateral direita, abaixo da Arena Top Voice e acima da Arena Sextante, ao lado da Área Coworking.',
        92.5, 60.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'espaco-mind', 'Espaço Mind', 'ativacao',
        array['mind espaço','espaco mind','espaço da mind']::text[],
        'Espaço Mind localizado no eixo central do evento.',
        'O Espaço Mind fica na região central inferior do mapa, à direita da Praça de Alimentação e à esquerda da Arena Sextante e da Livraria da Vila.',
        50.5, 77.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'praca-alimentacao', 'Praça de Alimentação', 'alimentacao',
        array['alimentação','comida','food court','praça de alimentação','restaurantes']::text[],
        'Praça de alimentação e food court.',
        'A Praça de Alimentação fica na parte inferior esquerda do mapa, abaixo da Arena Mind e à esquerda do Espaço Mind.',
        16.5, 75.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'barracas-alimentacao', 'Barracas de Alimentação', 'alimentacao',
        array['barracas','quiosques de comida','comida']::text[],
        'Barracas de alimentação indicadas junto à praça.',
        'As Barracas de Alimentação ficam ao longo da borda inferior da Praça de Alimentação, antes do corredor que leva à entrada.',
        39.5, 83.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'area-estandes', 'Área de Estandes', 'estandes',
        array['estandes','stands','área de stands']::text[],
        'Conjunto de estandes centrais sem nomes individuais visíveis no mapa fornecido.',
        'A Área de Estandes ocupa o corredor central, entre a Arena Mind e a Praça de Alimentação à esquerda e as arenas Top Voice e Sextante à direita.',
        51.0, 68.5, 'media', '{"verificada":false}'::jsonb
      ),
      (
        'credenciamento', 'Credenciamento', 'servico',
        array['retirada de credencial','retirar crachá','crachá','check-in']::text[],
        'Credenciamento para as categorias indicadas no mapa.',
        'O credenciamento fica na parte inferior direita do mapa, imediatamente acima da Entrada e da Saída.',
        75.0, 91.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'entrada-principal', 'Entrada Principal', 'acesso',
        array['entrada','acesso principal','portaria']::text[],
        'Entrada principal indicada no mapa.',
        'A Entrada Principal fica no canto inferior direito do mapa, ao lado da Saída e logo abaixo do credenciamento.',
        82.0, 94.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'saida-principal', 'Saída Principal', 'acesso',
        array['saída','saida','exit']::text[],
        'Saída principal indicada no mapa.',
        'A Saída Principal fica no canto inferior direito do mapa, à esquerda da Entrada e abaixo do credenciamento.',
        68.0, 94.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'banheiros-arena-mind', 'Banheiros próximos à Arena Mind', 'servico',
        array['banheiro arena mind','banheiros superiores','toalete arena mind']::text[],
        'Banheiros localizados próximos ao topo do mapa.',
        'Estes banheiros ficam próximos à parte superior do pavilhão, à direita do palco da Arena Mind e antes do conjunto de lounges.',
        65.0, 28.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'banheiros-entrada', 'Banheiros próximos à entrada', 'servico',
        array['banheiro entrada','banheiros inferiores','toalete entrada']::text[],
        'Banheiros localizados próximos à entrada.',
        'Estes banheiros ficam na parte inferior central, à esquerda do credenciamento, acima da chapelaria e das escadas.',
        44.5, 89.0, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'chapelaria', 'Chapelaria', 'servico',
        array['guarda-volumes','guardar casaco','casacos']::text[],
        'Chapelaria indicada no mapa.',
        'A Chapelaria fica na parte inferior central, à esquerda do credenciamento, entre os banheiros e as escadas.',
        44.5, 91.5, 'alta', '{"verificada":false}'::jsonb
      ),
      (
        'elevador-lateral-direita', 'Elevador da lateral direita', 'acessibilidade',
        array['elevador','lift']::text[],
        'Elevador indicado na lateral direita do mapa.',
        'O elevador fica na lateral direita, abaixo da Livraria da Vila e acima das escadas da mesma lateral.',
        93.0, 85.0, 'alta', '{"recurso":"elevador","verificada":true}'::jsonb
      ),
      (
        'escadas-lateral-direita', 'Escadas da lateral direita', 'acesso',
        array['escada direita','escadas perto do elevador']::text[],
        'Escadas indicadas na lateral direita.',
        'As escadas ficam na lateral direita, imediatamente abaixo do elevador.',
        93.0, 88.0, 'alta', '{"recurso":"escadas","acessivel":false,"verificada":true}'::jsonb
      ),
      (
        'escadas-chapelaria', 'Escadas próximas à chapelaria', 'acesso',
        array['escada chapelaria','escadas inferiores']::text[],
        'Escadas indicadas próximas à chapelaria.',
        'Estas escadas ficam na parte inferior central, abaixo da chapelaria e à esquerda do credenciamento.',
        44.5, 94.0, 'alta', '{"recurso":"escadas","acessivel":false,"verificada":true}'::jsonb
      ),
      (
        'foyer-traducao', 'Foyer de Tradução', 'servico',
        array['tradução','traducao','foyer tradução']::text[],
        'Ponto de tradução indicado próximo à Arena Mind.',
        'O Foyer de Tradução fica junto à saída inferior da Arena Mind, no corredor que liga a arena à Praça de Alimentação e à Área de Estandes.',
        27.0, 63.0, 'media', '{"verificada":false}'::jsonb
      )
  )
  insert into mind.locations (
    event_id, venue_id, slug, nome, tipo, aliases, descricao, como_chegar,
    andar, coordenadas_mapa, acessibilidade, ativo, atualizado_em
  )
  select
    v_event_id,
    v_venue_id,
    d.slug,
    d.nome,
    d.tipo,
    d.aliases,
    d.descricao,
    d.como_chegar,
    'Pavilhão 3',
    jsonb_build_object(
      'x_percent', d.x_percent,
      'y_percent', d.y_percent,
      'coordinate_system', 'imagem_completa_percentual',
      'source', 'mapa_oficial_mind_summit_2026',
      'confidence', d.confianca
    ),
    d.acessibilidade,
    true,
    now()
  from data d
  on conflict (event_id, slug) where slug is not null do update
  set venue_id = excluded.venue_id,
      nome = excluded.nome,
      tipo = excluded.tipo,
      aliases = excluded.aliases,
      descricao = excluded.descricao,
      como_chegar = excluded.como_chegar,
      andar = excluded.andar,
      coordenadas_mapa = excluded.coordenadas_mapa,
      acessibilidade = excluded.acessibilidade,
      ativo = true,
      atualizado_em = now();

  select id into strict v_entry_id
  from mind.locations
  where event_id = v_event_id and slug = 'entrada-principal';

  insert into mind.route_edges (
    event_id, origem_location_id, destino_location_id, instrucoes,
    distancia_metros, minutos_estimados, acessivel, bidirecional, ativo, metadata, atualizado_em
  )
  select
    v_event_id,
    v_entry_id,
    l.id,
    l.como_chegar,
    null,
    null,
    false,
    false,
    true,
    jsonb_build_object(
      'source', 'mapa_oficial_mind_summit_2026',
      'distance_verified', false,
      'accessibility_verified', false
    ),
    now()
  from mind.locations l
  where l.event_id = v_event_id
    and l.slug = any(array[
      'credenciamento','arena-mind','arena-top-voice','arena-sextante',
      'livraria-da-vila','lounge-prime','lounge-heineken','lounge-bwg',
      'area-coworking','mind-diversidade','espaco-mind','praca-alimentacao',
      'barracas-alimentacao','area-estandes','banheiros-arena-mind',
      'banheiros-entrada','chapelaria','elevador-lateral-direita',
      'escadas-lateral-direita','escadas-chapelaria','foyer-traducao'
    ])
  on conflict (event_id, origem_location_id, destino_location_id) do update
  set instrucoes = excluded.instrucoes,
      distancia_metros = excluded.distancia_metros,
      minutos_estimados = excluded.minutos_estimados,
      acessivel = excluded.acessivel,
      bidirecional = excluded.bidirecional,
      ativo = true,
      metadata = excluded.metadata,
      atualizado_em = now();
end
$migration$;

