-- Palestrantes, a partir de palestrantesmindsummit2026.xlsx (Adriana, 2026-08-22).
--
-- As bios ja estavam no banco byte a byte iguais as da planilha (conferido
-- por md5 nos 42), entao entram so as colunas novas: tipo, credencial e
-- frase_card, mais o asset_path das fotos que ela mandou.
--
-- cargo/organizacao NAO sao tocados: a credencial e uma linha de card e a
-- ordem varia ("Harvard . Seguranca psicologica" x "Neurociencia aplicada
-- . USP"), entao quebrar ela em dois campos seria chute — e o banco ja tem
-- os dois corretos.

alter table mind.speakers
  add column if not exists tipo text
    check (tipo in ('legend','nacional','internacional','internacional_online','mediacao')),
  add column if not exists credencial text,
  add column if not exists frase_card text;

comment on column mind.speakers.credencial is
  'Linha do card no site: "Harvard . Seguranca psicologica". Texto de exibicao, nao decomposto.';
comment on column mind.speakers.frase_card is
  'Resumo curto da bio, para card e para o agente citar sem despejar a bio inteira.';

update mind.speakers s set
  tipo = v.tipo,
  credencial = v.credencial,
  frase_card = nullif(v.frase_card, ''),
  asset_path = v.asset_path,
  atualizado_em = now()
from jsonb_to_recordset($j$[
{"nome":"Amy Edmondson","tipo":"legend","credencial":"Harvard · Segurança psicológica","frase_card":"Harvard. Eleita duas vezes pensadora nº 1 do mundo em gestão. Suas pesquisas guiam Google, hospitais e governos.","asset_path":"palestrantes/amy-edmondson.png"},
{"nome":"Christina Maslach","tipo":"legend","credencial":"Berkeley · Burnout","frase_card":"UC Berkeley. Criou o instrumento que mede burnout no mundo inteiro — base do reconhecimento pela OMS.","asset_path":"palestrantes/christina-maslach.png"},
{"nome":"Jan-Emmanuel De Neve","tipo":"legend","credencial":"Oxford · Economia do bem-estar","frase_card":"Oxford. Provou com 30 milhões de colaboradores que bem-estar é causa mensurável de resultado econômico.","asset_path":"palestrantes/jan-emmanuel-de-neve.png"},
{"nome":"Sonja Lyubomirsky","tipo":"legend","credencial":"UC Riverside · Felicidade","frase_card":"UC Riverside. 70 mil citações. Transformou a felicidade em um campo sólido de evidências — e de prática.","asset_path":"palestrantes/sonja-lyubomirsky.png"},
{"nome":"Adriana Drulla","tipo":"nacional","credencial":"Curadora e CEO do Mind","frase_card":"","asset_path":"palestrantes/adriana-drulla.png"},
{"nome":"Carla Tieppo","tipo":"nacional","credencial":"Neurociência aplicada · USP","frase_card":"","asset_path":"palestrantes/carla-tieppo.png"},
{"nome":"Ana Claudia Quintana Arantes","tipo":"nacional","credencial":"Finitude e significado","frase_card":"","asset_path":"palestrantes/ana-claudia-quintana-arantes.png"},
{"nome":"Márcio Atalla","tipo":"nacional","credencial":"Corpo e alta performance","frase_card":"","asset_path":"palestrantes/marcio-atalla.png"},
{"nome":"Arthur Guerra","tipo":"nacional","credencial":"Psiquiatria e performance","frase_card":"","asset_path":"palestrantes/arthur-guerra.png"},
{"nome":"Daniel de Barros","tipo":"nacional","credencial":"Psiquiatria · USP","frase_card":"","asset_path":"palestrantes/daniel-de-barros.png"},
{"nome":"Izabella Camargo","tipo":"nacional","credencial":"Produtividade sustentável","frase_card":"","asset_path":"palestrantes/izabella-camargo.png"},
{"nome":"Renata Rivetti","tipo":"nacional","credencial":"Felicidade no trabalho","frase_card":"","asset_path":"palestrantes/renata-rivetti.png"},
{"nome":"Tamara Myles","tipo":"internacional","credencial":"Trabalho significativo · UPenn","frase_card":"","asset_path":"palestrantes/tamara-myles.png"},
{"nome":"Deepika Chopra","tipo":"internacional_online","credencial":"The Optimism Doctor®","frase_card":"","asset_path":"palestrantes/deepika-chopra.png"},
{"nome":"Paul Goldsmith","tipo":"internacional","credencial":"Neurociência · Imperial College","frase_card":"","asset_path":"palestrantes/paul-goldsmith.png"},
{"nome":"Michael E. Long","tipo":"internacional_online","credencial":"Dopamina · Georgetown","frase_card":"","asset_path":"palestrantes/michael-e-long.png"},
{"nome":"Oscar de Bos","tipo":"internacional","credencial":"Economia da distração · Focus Academy","frase_card":"","asset_path":"palestrantes/oscar-de-bos.png"},
{"nome":"Gustavo Locatelli","tipo":"nacional","credencial":"Consultor e Médico do Trabalho","frase_card":"","asset_path":"palestrantes/gustavo-locatelli.png"},
{"nome":"Ana Bógus","tipo":"nacional","credencial":"Presidente · Beiersdorf Brasil","frase_card":"","asset_path":"palestrantes/ana-bogus.png"},
{"nome":"Mauro Muller","tipo":"nacional","credencial":"NR-1 · Ministério do Trabalho","frase_card":"","asset_path":"palestrantes/mauro-muller.png"},
{"nome":"Cirlene Zimmermann","tipo":"nacional","credencial":"Procuradora · MPT","frase_card":"","asset_path":"palestrantes/cirlene-zimmermann.png"},
{"nome":"Igor Menezes","tipo":"nacional","credencial":"People Analytics · University of Hull Inglaterra","frase_card":"","asset_path":"palestrantes/igor-menezes.png"},
{"nome":"Veruska Galvão","tipo":"nacional","credencial":"Segurança psicológica","frase_card":"","asset_path":"palestrantes/veruska-galvao.png"},
{"nome":"Edna Goldoni","tipo":"nacional","credencial":"Protagonismo · IVG","frase_card":"","asset_path":"palestrantes/edna-goldoni.png"},
{"nome":"João Yosef Torres","tipo":"nacional","credencial":"Diversidade e felicidade","frase_card":"","asset_path":"palestrantes/joao-yosef-torres.png"},
{"nome":"Alana Anijar","tipo":"nacional","credencial":"Inteligência emocional","frase_card":"","asset_path":"palestrantes/alana-anijar.png"},
{"nome":"Yuri Trafane","tipo":"nacional","credencial":"Engajamento · Ynner","frase_card":"","asset_path":"palestrantes/yuri-trafane.png"},
{"nome":"Fernanda Catena","tipo":"nacional","credencial":"Longevidade e saúde","frase_card":"","asset_path":"palestrantes/fernanda-catena.png"},
{"nome":"Maryana com Y","tipo":"nacional","credencial":"Inteligência HUMORcional","frase_card":"","asset_path":"palestrantes/maryana-com-y.png"},
{"nome":"Irene Reis","tipo":"nacional","credencial":"Educação e saúde mental","frase_card":"","asset_path":"palestrantes/irene-reis.png"},
{"nome":"Lailson Lima","tipo":"nacional","credencial":"Segurança do trabalho · ConCuidado","frase_card":"","asset_path":"palestrantes/lailson-lima.png"},
{"nome":"Michelle Schneider","tipo":"nacional","credencial":"IA e futuro do trabalho","frase_card":"","asset_path":"palestrantes/michelle-schneider.png"},
{"nome":"Daiana Garbin","tipo":"nacional","credencial":"Saúde mental e autocompaixão","frase_card":"","asset_path":"palestrantes/daiana-garbin.png"},
{"nome":"Ana Mocny","tipo":"nacional","credencial":"Sócia Capital humano · Deloitte","frase_card":"","asset_path":"palestrantes/ana-mocny.png"},
{"nome":"Esabela Cruz","tipo":"nacional","credencial":"Cultura e gestão de pessoas","frase_card":"","asset_path":"palestrantes/esabela-cruz.png"},
{"nome":"Ivana Moreira","tipo":"nacional","credencial":"Cofundadora do Mind Summit","frase_card":"","asset_path":"palestrantes/ivana-moreira.png"},
{"nome":"Maurício Giamellaro","tipo":"nacional","credencial":"CEO · HEINEKEN Brasil","frase_card":"","asset_path":"palestrantes/mauricio-giamellaro.png"},
{"nome":"Paula Benevides","tipo":"nacional","credencial":"VP de Pessoas, Cultura e Organização · Natura","frase_card":"","asset_path":"palestrantes/paula-benevides.png"},
{"nome":"Caito Maia","tipo":"nacional","credencial":"Fundador e CEO · Chilli Beans","frase_card":"","asset_path":"palestrantes/caito-maia.png"},
{"nome":"Denize Savi","tipo":"nacional","credencial":"Diretora de Felicidade · Chilli Beans","frase_card":"","asset_path":"palestrantes/denize-savi.png"},
{"nome":"Denise Salvador","tipo":"nacional","credencial":"Psicóloga · coach executiva","frase_card":"","asset_path":"palestrantes/denise-salvador.png"},
{"nome":"Daniel Izzo","tipo":"nacional","credencial":"Cofundador e sócio · Vox Capital","frase_card":"","asset_path":"palestrantes/daniel-izzo.png"}
]$j$::jsonb) as v(nome text, tipo text, credencial text, frase_card text, asset_path text)
where s.nome = v.nome;

-- Aparecem so como mediadoras na programacao; sem bio na planilha.
update mind.speakers set tipo = 'mediacao', atualizado_em = now()
 where nome in ('Sibelle Pedral','Virginie Leite') and tipo is null;
