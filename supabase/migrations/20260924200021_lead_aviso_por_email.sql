-- Aviso de lead por e-mail (decisão da Adriana em 24/09/2026): "quando alguém mostrar interesse em
-- Institute ou Dash ... ele pode enviar um email para thiago@joinmind.com.br e diego@joinmind.com.br e
-- adriana@joinmind.com.br (mesmo email)". Envio pelo Resend, que a empresa já usa.
--
-- Casa existente: `intelligence.sinais_comerciais` (mind_id, produto, força, evidência, mensagem,
-- status) — criada para isto e ainda vazia. Uma linha por pessoa e vertical a cada 7 dias: é o
-- registro do lead e a trava contra e-mail repetido.
--
--   1. `intelligence.config`: destinatários e remetente, editáveis sem código;
--   2. `public.mind_lead_aviso_dados` / `mind_lead_aviso_marcar`: o que a Edge Function lê e grava;
--   3. gatilho em `engagement.mensagens`: resposta do agente nas rotas `institute`/`dash` para uma
--      pessoa que é lead e tem WhatsApp ou e-mail → registra o sinal e chama a Edge Function
--      `lead-aviso` pela porta interna (pg_net, assíncrono). Qualquer erro vira warning: a conversa
--      nunca é bloqueada.
--
-- Sem `RESEND_API_KEY` nos secrets das Edge Functions, a função responde erro e o sinal fica `novo`;
-- dá para reenviar depois com `select public.mind_lead_aviso_disparar(<sinal_id>)`.
-- Reversível: `drop trigger mensagens_lead_aviso on engagement.mensagens`.

insert into intelligence.config (chave, valor) values
  ('lead_aviso_destinatarios', '["thiago@joinmind.com.br","diego@joinmind.com.br","adriana@joinmind.com.br"]'),
  ('lead_aviso_remetente', 'Mind Agent <agente@joinmind.com.br>')
on conflict (chave) do nothing;

create or replace function public.mind_lead_aviso_dados(p_sinal_id uuid)
returns jsonb
language sql stable security definer
set search_path to ''
as $fn$
  select jsonb_build_object(
    'sinal', jsonb_build_object('id', s.id, 'vertical', s.vertical, 'produto', s.produto_codigo,
                                'status', s.status, 'criado_em', s.criado_em),
    'pessoa', jsonb_strip_nulls(jsonb_build_object(
      'nome', nullif(btrim(concat_ws(' ', p.primeiro_nome, p.sobrenome)), ''),
      'email', p.email, 'whatsapp', p.whatsapp, 'cargo', p.cargo, 'empresa', p.empresa,
      'icp', (select i.rotulo from intelligence.icp i where i.codigo = p.icp),
      'ingresso_summit_2026', public.mind_credenciamento_fatos(p.id)->'categorias')),
    'conversa', coalesce((
      select jsonb_agg(jsonb_build_object('papel', x.papel, 'texto', left(x.conteudo, 1200)) order by x.criado_em)
        from (select m.papel, m.conteudo, m.criado_em
                from engagement.mensagens m
               where m.conversa_id = (select m0.conversa_id from engagement.mensagens m0 where m0.id = s.mensagem_id)
                 and m.papel in ('lead', 'agente') and m.conteudo is not null
               order by m.criado_em desc limit 10) x), '[]'::jsonb),
    'destinatarios', (select c.valor::jsonb from intelligence.config c where c.chave = 'lead_aviso_destinatarios'),
    'remetente', (select c.valor from intelligence.config c where c.chave = 'lead_aviso_remetente'))
  from intelligence.sinais_comerciais s
  join pessoas.pessoas p on p.id = s.mind_id
  where s.id = p_sinal_id;
$fn$;
revoke all on function public.mind_lead_aviso_dados(uuid) from public, anon, authenticated;
grant execute on function public.mind_lead_aviso_dados(uuid) to service_role;

create or replace function public.mind_lead_aviso_marcar(p_sinal_id uuid, p_status text, p_observacao text)
returns void
language sql security definer
set search_path to ''
as $fn$
  update intelligence.sinais_comerciais
     set status = p_status, observacao = left(p_observacao, 500)
   where id = p_sinal_id;
$fn$;
revoke all on function public.mind_lead_aviso_marcar(uuid, text, text) from public, anon, authenticated;
grant execute on function public.mind_lead_aviso_marcar(uuid, text, text) to service_role;

create or replace function public.mind_lead_aviso_disparar(p_sinal_id uuid)
returns bigint
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'platform', 'intelligence'
as $fn$
declare v_base text; v_key text; v_token text;
begin
  select i.base_url, i.config->>'anon_key' into v_base, v_key
    from platform.integracoes i where i.codigo = 'supabase_functions' and i.ativo;
  select c.valor into v_token from intelligence.config c where c.chave = 'analise_token';
  if v_base is null or v_key is null or v_token is null then
    raise exception 'mind_lead_aviso_disparar: integração supabase_functions ou analise_token ausentes';
  end if;
  return net.http_post(
    url := v_base || '/lead-aviso',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_key),
    body := jsonb_build_object('token', v_token, 'sinal_id', p_sinal_id),
    timeout_milliseconds := 30000);
end $fn$;
revoke execute on function public.mind_lead_aviso_disparar(uuid) from public, anon, authenticated;

create or replace function intelligence.lead_aviso_detectar()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'intelligence', 'engagement', 'pessoas'
as $fn$
declare
  v_rota text := new.blocos->>'rota';
  v_pessoa uuid;
  v_evidencia text;
  v_sinal uuid;
begin
  if new.papel <> 'agente' or v_rota is null or v_rota not in ('institute', 'dash') then
    return null;
  end if;

  select coalesce(new.mind_id, c.mind_id) into v_pessoa
    from engagement.conversas c where c.id = new.conversa_id;
  v_pessoa := coalesce(public.mind_pessoa_canonica(v_pessoa), v_pessoa);
  if v_pessoa is null then return null; end if;

  -- só lead com contato; staff, palestrante, professor e parceiro não são lead
  if not exists (
    select 1 from pessoas.pessoas p
     where p.id = v_pessoa
       and (p.whatsapp is not null or p.email is not null)
       and coalesce(p.relacionamento_mind, array['lead']) = array['lead']) then
    return null;
  end if;

  if exists (
    select 1 from intelligence.sinais_comerciais s
     where s.mind_id = v_pessoa and s.vertical = v_rota and s.criado_em > now() - interval '7 days') then
    return null;
  end if;

  select left(m.conteudo, 1000) into v_evidencia
    from engagement.mensagens m
   where m.conversa_id = new.conversa_id and m.papel = 'lead' and m.conteudo is not null
   order by m.criado_em desc limit 1;

  insert into intelligence.sinais_comerciais
    (mind_id, vertical, produto_codigo, forca, evidencia_texto, mensagem_id, canal_preferido, status)
  values
    (v_pessoa, v_rota, case v_rota when 'institute' then 'mind-institute' else 'mind-dash' end,
     'media', coalesce(v_evidencia, '(sem texto)'), new.id, 'whatsapp', 'novo')
  returning id into v_sinal;

  perform public.mind_lead_aviso_disparar(v_sinal);
  return null;
exception when others then
  raise warning 'lead_aviso_detectar: % (a mensagem foi gravada)', sqlerrm;
  return null;
end $fn$;

drop trigger if exists mensagens_lead_aviso on engagement.mensagens;
create trigger mensagens_lead_aviso
  after insert on engagement.mensagens
  for each row
  when (new.papel = 'agente' and new.blocos ? 'rota')
  execute function intelligence.lead_aviso_detectar();

comment on function intelligence.lead_aviso_detectar() is
  'Gatilho em engagement.mensagens: resposta do agente nas rotas institute/dash para um lead com contato registra intelligence.sinais_comerciais (1 por pessoa e vertical a cada 7 dias) e chama a Edge Function lead-aviso (e-mail ao time pelo Resend). Erro vira warning.';
