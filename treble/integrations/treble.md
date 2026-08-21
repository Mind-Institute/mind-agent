# Integração Treble — contrato e roteiro de configuração

> Status: contrato definido; roteiro passo a passo será completado na
> Fase 3 (ver `../docs/06_PLANO_EXECUCAO.md`), com prints do painel.

## Mecanismo (documentação oficial do Treble)

- **Webhook de resposta**: cada bloco de mensagem do fluxo salva a resposta
  do usuário em variável e envia POST ao nosso endpoint com a mensagem,
  as variáveis e o `session_external_id`. Resposta em < 10 s volta ao fluxo.
- **`[REQUEST_TRIGGER]`**: bloco que pausa a conversa até o nosso servidor
  chamar `POST /session/{session_external_id}/update` com a resposta e
  `user_session_keys`.
- Referências: guia "Integrate Your Own AI in Treble", páginas de webhooks
  e endpoints em help.treble.ai (API key na seção Developers do painel).

## Fluxo fino no Conversation Builder

```
entrada (saudação + salvar resposta)
  → webhook → [REQUEST_TRIGGER] → mensagem com {{resposta_do_cerebro}}
  → loop de conversa
  rotas fixas: needs_human=true → transferir ao inbox (vendedores)
               opt-out → descadastro
```

## Variáveis de sessão espelhadas

`intent` · `stage` · `needs_human` · `checkout_sent` — o estado completo
vive na tabela `conversations` do Supabase.

## Segurança

- `TREBLE_API_KEY` e `TREBLE_WEBHOOK_SECRET`: só nas env vars da Edge
  Function. Nunca no repositório, nunca em chat.
- O webhook valida a origem antes de processar.
