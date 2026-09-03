-- Contrato do vendedor B2B Summit.
-- Leitura apenas; não cria fixture nem altera dados.

do $test$
declare
  v_b2b text;
  v_b2c text;
begin
  select public.treble_agent_prompt('summit_b2b','completo') into v_b2b;
  select public.treble_agent_prompt('summit_b2c','completo') into v_b2c;

  if position('MODO CORPORATIVO — SUMMIT B2B' in coalesce(v_b2b,'')) = 0 then
    raise exception 'playbook B2B novo ausente';
  end if;
  if position('https://pdf.mindsummit.company/' in coalesce(v_b2b,'')) = 0 then
    raise exception 'material de aprovação ausente do B2B';
  end if;
  if position('nome e sobrenome' in coalesce(v_b2b,'')) = 0
     or position('empresa' in coalesce(v_b2b,'')) = 0
     or position('cargo' in coalesce(v_b2b,'')) = 0
     or position('e-mail' in coalesce(v_b2b,'')) = 0 then
    raise exception 'campos progressivos ausentes do B2B';
  end if;
  if position('Classifique quem chegou:' in coalesce(v_b2b,'')) > 0 then
    raise exception 'playbook_router ainda foi montado no B2B';
  end if;
  if position('Classifique quem chegou:' in coalesce(v_b2c,'')) > 0 then
    raise exception 'playbook_router ainda foi montado no B2C';
  end if;
  if position('CONTA DE GRUPO' in coalesce(v_b2c,'')) > 0 then
    raise exception 'playbook B2B vazou para o B2C';
  end if;
end
$test$;
