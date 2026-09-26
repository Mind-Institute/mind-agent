-- Passo 10 (Adriana, 24/09/2026): a cópia diária de empresa do HubSpot (crm.empresa_pessoas) não
-- traz de volta a sujeira que a limpeza apagou de pessoas.pessoas — "Autônoma", "Nenhuma", "Sem
-- empresa", "Profissional liberal", "Psicóloga", "Consultora", "Particular", "Freelancer" no texto
-- livre, e companies do HubSpot chamadas "Autônomo …". Reescrita a partir da definição viva, com trava.
do $$
declare def text; novo text;
begin
  def := pg_get_functiondef('crm.empresa_pessoas()'::regprocedure);
  if def like '%autonom|nenhum%' then return; end if;  -- já aplicado
  novo := replace(def,
    $a$'^(teste|nao tenho|nao|domain|agencia de marketing|empresa|minha empresa)\M'$a$,
    $a$'^(teste|nao tenho|nao|domain|agencia de marketing|empresa|minha empresa|autonom|nenhum|sem empresa|profissional liberal|psicolog|particular|freela|consultora?$)\M'$a$);
  novo := replace(novo,
    $a$'^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|icloud|uol|bol|terra|ig|globo|aol|protonmail|e-?mail)(\.com)?$'),$a$,
    $a$'^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|icloud|uol|bol|terra|ig|globo|aol|protonmail|e-?mail)(\.com)?$'
       and btrim(e.name) !~* '^aut[oô]nom'),$a$);
  if novo = def or position('autonom|nenhum' in novo) = 0 or position($a$!~* '^aut[oô]nom'$a$ in novo) = 0 then
    raise exception 'crm.empresa_pessoas: trecho esperado não encontrado';
  end if;
  execute novo;
end $$;

-- Companies automáticas do HubSpot criadas a partir de e-mail com typo ("gmai.com", "Gamil") também não
-- trazem empresa.
do $$
declare def text; novo text;
begin
  def := pg_get_functiondef('crm.empresa_pessoas()'::regprocedure);
  if def like '%gmai|gamil%' then return; end if;
  novo := replace(def,
    $a$and btrim(e.name) !~* '^aut[oô]nom'),$a$,
    $a$and btrim(e.name) !~* '^aut[oô]nom'
       and btrim(e.name) !~* '^(gmai|gamil|gmal|gnail|hormail|hotmai|icoud|iclaud|icour|outlok)(\.com.*)?$'),$a$);
  if novo = def then raise exception 'crm.empresa_pessoas: trecho esperado não encontrado'; end if;
  execute novo;
end $$;

-- Company do HubSpot com domínio de provedor de e-mail (ex.: "Ecossistema do Futuro" com gmail.com) faz o
-- HubSpot associar a ela todo contato daquele provedor. Associação a essas companies não vale como empresa.
do $$
declare def text; novo text;
begin
  def := pg_get_functiondef('crm.empresa_pessoas()'::regprocedure);
  if def like '%dominio de provedor%' then return; end if;
  novo := replace(def,
    $a$and btrim(e.name) !~* '^(gmai|gamil|gmal|gnail|hormail|hotmai|icoud|iclaud|icour|outlok)(\.com.*)?$'),$a$,
    $a$and btrim(e.name) !~* '^(gmai|gamil|gmal|gnail|hormail|hotmai|icoud|iclaud|icour|outlok)(\.com.*)?$'
       -- dominio de provedor
       and lower(regexp_replace(coalesce(e.domain, ''), '^(https?://)?(www\.)?', ''))
           !~ '^(gmail|googlemail|hotmail|outlook|live|msn|yahoo|ymail|icloud|me|mac|uol|bol|terra|ig|aol|protonmail|gmai|gamil|gmal|gnail|hormail|icoud|iclaud|icour|icourd|outly)\.'),$a$);
  if novo = def then raise exception 'crm.empresa_pessoas: trecho esperado não encontrado'; end if;
  execute novo;
end $$;
