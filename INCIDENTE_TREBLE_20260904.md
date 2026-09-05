# Incidente Treble — rota, checkout e latência

Data: 04/09/2026

## Sintomas confirmados

- uma pessoa disse “Sou gestora” e foi enviada de B2C para B2B;
- ao pedir o link do VIP, o Agent reteve o checkout e pediu nome completo;
- o turno seguinte sobre o nome foi classificado como suporte e virou handoff;
- o Router consumiu mediana de 6,7 s, p90 de 8,9 s e falhou em 5 de 15 turnos
  observados nas 48 horas anteriores.

## Causa

1. O Router era chamado em todo turno, embora o canal seja predominantemente
   comercial B2C.
2. Prompt e runtime tratavam nome, e-mail, WhatsApp, empresa e cargo como
   pré-condição transacional.
3. O decisioning dizia simultaneamente “proteja o momentum” e “não entregue
   checkout antes do cadastro”.
4. O cargo foi usado pelo modelo como evidência de B2B, contrariando o próprio
   contrato: B2B/B2C classifica a compra atual, não a pessoa.

O lead do caso estava encontrado: pessoa, identidade de WhatsApp, nome da conversa
e contato no espelho do CRM existiam. O defeito foi interpretar sobrenome ausente
como impedimento para vender.

## Correção publicada

- PR #98 mergeada em `main` no commit
  `2581f6632339b4606f887d340b6c00821de9a3c5`;
- `treble-inbound-agent` v41, runtime interno `1.10.2`;
- `router_universal` ativo na v4;
- B2C é o padrão do canal comercial;
- para venda de ingressos, B2B exige ao mesmo tempo destino corporativo e mais
  de uma pessoa;
- cargo, empresa, pagamento corporativo de um único ingresso, quantidade sem
  destino corporativo ou potencial futuro não alteram uma compra individual;
- compras para casal, família ou amigos continuam B2C;
- destino corporativo sem quantidade volta ao Router para esclarecimento;
- patrocínio permanece B2B como demanda própria;
- suporte explícito continua usando o Router universal;
- checkout, preço, recomendação, proposta e calculadora não são mais bloqueados
  por cadastro;
- o estado legado `coleta_cadastro` é neutralizado antes de chegar ao modelo;
- `rota_origem` registra por que o turno foi B2C, B2B ou enviado ao Router.

## Correção adicional — checkout, preço e handoff

Publicada em 04/09/2026 na Edge Function v43, runtime interno `1.11.0`:

- o WhatsApp entrega o checkout oficial diretamente em `sun.eduzz.com`, sem
  redirecionador Supabase, UUID ou identificadores internos visíveis;
- quatro UTMs concisas preservam a atribuição de conversão na Eduzz:
  `utm_source=whatsapp`, `utm_medium=ai_agent`, `utm_campaign=ms26` e
  `utm_content=treble_<categoria>`;
- preços parcelados aparecem antes do total, por exemplo:
  “O VIP está 12x R$ 225 no lote vigente (R$ 2.697).”;
- mudança, comparação ou dúvida entre Mind, VIP e Prime não acende handoff;
- `needs_human=true` do modelo só é aceito quando acompanhado de um motivo
  operacional enumerado. O Capability Gate continua soberano para limitações
  reais do canal/runtime.

O patch do prompt foi aplicado somente em `decisioning_vendas_universal`, da
versão 2 para a 3. A migração exige o SHA original, uma âncora única e prova de
reversibilidade. Os hashes dos playbooks `playbook_summit_b2c` e
`playbook_summit_b2b` são verificados e permaneceram inalterados.

A mensagem pronta de transferência observada após “quero entender mais do
Prime” não foi produzida pelo Agent: não tinha rota, modelo, versão ou request ID
e o estado da conversa continuou com `needs_human=false`. Ela veio do
timeout/fallback externo do fluxo Treble. Essa copy e esse timeout não estão
versionados neste repositório e precisam ser validados no teste controlado da
plataforma.

## Provas

- 185/185 testes Edge na correção da PR #98;
- 17/17 casos específicos do classificador comercial;
- 15/15 verificações estáticas do runtime B2B;
- 76/76 contratos do guardrail de preço;
- migration do Router passou em `BEGIN/ROLLBACK` contra o prompt vivo e contém
  uma prova reversível de que somente o bloco B2B/B2C foi substituído;
- health vivo respondeu `{"ok":true,"service":"treble-inbound-agent","version":"1.10.2"}`;
- contrato SQL do playbook passou contra produção;
- “Sou gestora e quero comprar um ingresso para mim” → `summit_b2c`,
  `router_ms=0`;
- “Minha empresa vai pagar meu ingresso” → `summit_b2c`;
- “Quero dois ingressos para mim e meu marido” → `summit_b2c`;
- “Quero 5 ingressos” → `summit_b2c`;
- “Quero comprar ingressos para minha empresa” → Router para esclarecer
  quantidade;
- “Quero comprar o VIP. Me manda o link agora” → checkout oficial rastreado,
  sem pergunta cadastral, 4,48 s;
- “Quero levar 5 pessoas da minha equipe” → `summit_b2b`, valores oficiais
  por volume e calculadora.
- após a correção adicional: 194/194 testes da suíte principal e contratos
  específicos de handoff, checkout direto, resposta não truncada e preço.

## Limite da prova

O smoke confirma o retorno HTTP do runtime. A confirmação de que a Treble exibiu a
mensagem no aparelho continua sendo um teste externo necessário antes da abertura.

## Correção operacional — síncrono abaixo de 10 segundos

Publicada em 05/09/2026 na Edge Function v48, runtime interno `1.14.0`:

- a URL síncrona e o token permaneceram os mesmos, sem `request_trigger=1`;
- o orçamento total do caminho síncrono passou a 7,5 s, deixando margem antes do
  timeout de 10 s documentado pela Treble;
- perguntas comerciais diretas usam os fatos completos do Kit sem abrir uma segunda
  rodada de Intelligence;
- “condição especial” sem Mind/VIP/Prime recebe uma pergunta determinística de escolha,
  sem modelo e sem handoff;
- se uma etapa ainda estourar o orçamento, a Edge devolve uma resposta válida com
  `needs_human=true` antes do timeout e grava o diagnóstico no histórico pelo mesmo
  `request_id`, sem bloquear a resposta;
- prompts, preços, checkout Eduzz, UTMs e regras comerciais foram preservados.

Provas em produção na v47, republicada sem mudança funcional como v48 para manter o
fonte documentado idêntico ao artefato ativo:

- “Quero saber da condição especial” → HTTP 200, `needs_human=false`, 1,998 s;
- “VIP” no turno seguinte → 12x de R$225 antes de R$2.697, checkout Eduzz com UTMs,
  `needs_human=false`, 4,143 s;
- “Quero ver o Prime” depois do VIP → sem handoff, checkout Eduzz, 3,844 s;
- pergunta pesada de programação → timeout interno em 7,501 s, resposta válida em
  7,630 s e mensagem persistida com `erro_runtime=timeout`.

A suíte passou com 211/211 testes Edge, 76/76 contratos do guardrail e todos os
contratos específicos de Treble, B2B e falha sem silêncio. Falta somente observar a
entrega no WhatsApp real, que continua sendo um gate externo da Treble/Meta.

## Correção de transporte — Request Trigger assíncrono

Publicada em 05/09/2026 na Edge Function v45, runtime interno `1.12.1`:

- o endpoint síncrono anterior permanece intacto;
- a URL com `request_trigger=1` confirma o webhook com HTTP 202 antes de chamar
  Router ou IA e mantém o processamento em background com `EdgeRuntime.waitUntil`;
- ao terminar, o backend atualiza a sessão original pela API oficial da Treble e envia
  as mesmas `user_session_keys` que o fluxo já consome;
- a credencial `TREBLE_API_KEY` já existia no projeto e não foi duplicada;
- dois probes sem escrita mediram 147 ms e 168 ms de execução até o 202 nos logs da
  Supabase;
- a suíte principal passou 201/201. Nenhum prompt ou comportamento comercial mudou.

Após o primeiro teste no Editor, a documentação oficial do webhook de resposta revelou
que a fala do lead chega em `actual_response`. O runtime passou a ler esse campo como
fonte prioritária e explicitamente não usa `question.text`, que é a pergunta do fluxo.
A suíte principal permaneceu aprovada em 201/201.

No mesmo teste, os logs provaram que nenhum POST chegou ao `treble-inbound-agent`; houve
somente um evento no `treble-webhook`, receptor geral de eventos de sessão que não roda
IA. Portanto, o bloqueio observado ocorreu antes do backend: a sessão alcançou o bloco
de espera sem disparar a URL do Agent. O próximo teste deve confirmar a URL na linha de
entrada do `[REQUEST_TRIGGER]`, publicar a versão e iniciar uma sessão nova.

O modo ficou opt-in para evitar quebrar o fluxo antes da alteração no Editor da Treble.
Para ativá-lo, o webhook da linha que chega ao novo bloco `[REQUEST_TRIGGER]` deve usar
a URL atual acrescida de `&request_trigger=1`. O Alternate Flow de 5 minutos deve ficar
nesse bloco de espera; no bloco `{{resposta_ia}}`, ele representa inatividade posterior
à resposta e não timeout da IA. A prova final continua sendo um turno entregue no
WhatsApp real, acompanhado do evento `treble_request_trigger_concluido`.
