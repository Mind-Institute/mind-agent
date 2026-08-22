-- Porta dos agentes comerciais: devolve o conversável MAIS os sinais
-- internos. Existe separada de crm.buscar_pessoa para que a diferença
-- entre "o bot pode dizer" e "o bot só leva em conta" seja uma escolha
-- de qual função chamar — visível em código e auditável — e não uma
-- linha de prompt pedindo discrição.
create or replace function crm.contexto_comercial(
  p_email text default null,
  p_whatsapp text default null,
  p_agente text default 'vendas'
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'crm', 'catalogo'
as $$
declare
  v_base jsonb;
  v_id uuid;
  v_int crm.pessoas_interno%rowtype;
begin
  v_base := crm.buscar_pessoa(p_email, p_whatsapp, p_agente);
  if coalesce((v_base->>'encontrado')::boolean, false) is not true then
    return v_base;
  end if;

  v_id := (v_base->>'id')::uuid;
  select * into v_int from crm.pessoas_interno where pessoa_id = v_id;

  insert into crm.acessos (funcao, pessoa_id, agente)
  values ('crm.contexto_comercial', v_id, coalesce(p_agente, 'vendas'));

  return v_base || jsonb_build_object(
    'interno', jsonb_build_object(
      'origem_primeira', v_int.origem_primeira,
      'origem_ultima', v_int.origem_ultima,
      'utm', jsonb_strip_nulls(jsonb_build_object(
        'source', v_int.utm_source, 'medium', v_int.utm_medium,
        'campaign', v_int.utm_campaign, 'content', v_int.utm_content,
        'term', v_int.utm_term)),
      'dono', jsonb_strip_nulls(jsonb_build_object(
        'id', v_int.dono_id, 'nome', v_int.dono_nome)),
      'status_lead', v_int.status_lead,
      'negocios_associados', v_int.negocios_associados,
      'ultimo_contato_em', v_int.ultimo_contato_em,
      'perfil_cliente', v_int.perfil_cliente,
      'descadastrado_email', coalesce(v_int.descadastrado_email, false),
      'nps', coalesce((
        select jsonb_agg(jsonb_build_object(
          'produto', n.produto_codigo, 'nota', n.nota,
          'comentario', n.comentario, 'em', n.respondido_em))
        from crm.pessoa_nps n where n.pessoa_id = v_id
      ), '[]'::jsonb)
    ),
    'uso_interno', 'Estes sinais orientam tom e argumento. Nunca os repita ao usuario, nem confirme que existem.'
  );
end;
$$;

comment on function crm.contexto_comercial is
  'Contexto completo para agentes comerciais: conversavel + sinais internos. Bots de atendimento devem usar crm.buscar_pessoa, que nao alcanca o interno.';

revoke all on function crm.contexto_comercial(text, text, text) from public, anon, authenticated;
