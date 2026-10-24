-- Carga das pesquisas 2024/2025 (uma vez). Cada linha: [ref, c0, c1, ...] na ordem do cabeçalho da planilha.
-- A pessoa é resolvida/criada pela porta única mind_identidade_resolver antes da gravação (Regra #1).
create or replace function public.mind_pesquisa_carregar(p_pesquisa text, p_cabecalho jsonb, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'engagement', 'pessoas'
as $$
declare x jsonb; v_email text; v_mind uuid; v_resp jsonb; n int := 0; com_mind int := 0; i int;
  num text := '^\s*-?\d+(\.\d+)?\s*$';
begin
  for x in select * from jsonb_array_elements(p_linhas) loop
    v_resp := '{}'::jsonb;
    for i in 0 .. jsonb_array_length(p_cabecalho) - 1 loop
      if x->(i + case when p_pesquisa = 'interesse_2025' then 2 else 1 end) is not null
         and jsonb_typeof(x->(i + case when p_pesquisa = 'interesse_2025' then 2 else 1 end)) <> 'null' then
        v_resp := v_resp || jsonb_build_object(p_cabecalho->>i, x->(i + case when p_pesquisa = 'interesse_2025' then 2 else 1 end));
      end if;
    end loop;
    v_email := lower(nullif(btrim(case when p_pesquisa = 'interesse_2025' then x->>1 else x->>2 end), ''));
    if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' then v_email := null; end if;
    v_mind := null;
    if v_email is not null then
      v_mind := (public.mind_identidade_resolver(jsonb_build_object('email', v_email), null, 'pesquisa', null, true)->>'pessoa_id')::uuid;
    end if;
    if p_pesquisa = '2024' then
      insert into engagement.pesquisa_summit_2024 (resposta_ref, respondido_em, email_informado, mind_id, experiencia, profissao,
             nota_expectativa, nota_organizacao, nota_conteudo, nota_aplicabilidade, aceita_contato, respostas)
      values ('linha ' || (x->>0), (x->>1)::timestamp at time zone 'America/Sao_Paulo', v_email, v_mind, x->>3, x->>4,
              case when x->>7 ~ num then (x->>7)::numeric end, case when x->>9 ~ num then (x->>9)::numeric end,
              case when x->>11 ~ num then (x->>11)::numeric end, case when x->>12 ~ num then (x->>12)::numeric end,
              x->>32, v_resp)
      on conflict (resposta_ref) do nothing;
    elsif p_pesquisa = '2025' then
      insert into engagement.pesquisa_summit_2025 (resposta_ref, respondido_em, email_informado, mind_id, experiencia, profissao, nps,
             nota_curadoria, nota_organizacao, nota_infraestrutura, nota_comunicacao, nota_conteudo, nota_aplicabilidade,
             interesse_continuar, aceita_contato, respostas)
      values ('linha ' || (x->>0), (x->>1)::timestamp at time zone 'America/Sao_Paulo', v_email, v_mind, x->>3, x->>4,
              case when x->>5 ~ num then (x->>5)::numeric::smallint end,
              case when x->>8 ~ num then (x->>8)::numeric end, case when x->>9 ~ num then (x->>9)::numeric end,
              case when x->>10 ~ num then (x->>10)::numeric end, case when x->>11 ~ num then (x->>11)::numeric end,
              case when x->>12 ~ num then (x->>12)::numeric end, case when x->>13 ~ num then (x->>13)::numeric end,
              x->>28, x->>30, v_resp)
      on conflict (resposta_ref) do nothing;
    elsif p_pesquisa = 'interesse_2025' then
      insert into engagement.pesquisa_interesse_2025 (resposta_ref, respondido_em, concluida, email_informado, mind_id, funcao, respostas)
      values (x->>0, (x->>3)::timestamp at time zone 'America/Sao_Paulo', lower(coalesce(x->>6, '')) in ('true', '1', 'verdadeiro'),
              v_email, v_mind, v_resp->>(select k from jsonb_object_keys(v_resp) k where k like 'QID3 ·%' limit 1), v_resp)
      on conflict (resposta_ref) do nothing;
    else
      raise exception 'pesquisa desconhecida %', p_pesquisa;
    end if;
    n := n + 1; if v_mind is not null then com_mind := com_mind + 1; end if;
  end loop;
  return jsonb_build_object('linhas', n, 'com_mind_id', com_mind);
end $$;
revoke all on function public.mind_pesquisa_carregar(text, jsonb, jsonb) from public, anon, authenticated;
