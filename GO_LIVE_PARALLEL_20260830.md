# Go-live 30/08/2026 — execução paralela

> Complemento operacional de `GO_LIVE_VENDEDOR_CONCIERGE_20260830.md`.
> A ordem canônica continua sendo a ordem de integração/deploy. O trabalho preparatório pode ocorrer em paralelo em lanes isoladas.

## Regra central

**Ordem de deploy não é ordem de trabalho.**

Cada lane trabalha em branch própria. Nenhum lane altera componente de outro lane. Todos podem investigar e preparar implementação em paralelo; integração e merge seguem as dependências canônicas.

## Lanes

### Lane A — Core / DB / Gate

Responsável por:
- #36 `mind_kit_meta` + `mind_agent_kit`;
- depois, mudança mínima do Capability Gate para ler `mind_kit_meta`;
- não toca Decisioning/Agent/Treble/Concierge.

Estado inicial deste documento:
- #37 mergeada;
- #38 mergeada;
- produção com 81 `session_speakers`, zero `speaker_id` nulo, zero duplicata;
- #36 aberta e em atualização sobre main.

### Lane B — Vendedor Summit / runtime Treble

Responsável por:
- investigar runtime vivo do `treble-inbound-agent`;
- preparar o menor patch para usar os contratos congelados de Router → Gate → Kit → Decisioning → Agent → resposta/handoff;
- B2C e B2B;
- preservar contrato de entrada/saída do Treble;
- não altera #36, providers, Gate, schema de Intelligence ou Concierge.

Pode trabalhar antes do merge da #36 usando as assinaturas já congeladas, mas deve atualizar com main e fazer teste final depois de #36 + Gate.

### Lane C — Concierge Summit

Responsável por:
- investigar o runtime/superfície viva do concierge;
- reutilizar `summit_2026.sessions`, `session_speakers`, `ecossistema.palestrantes_especialistas` e retrieval vivo existente;
- preparar resposta factual de programação, horários, espaços, sessões e palestrantes;
- recomendação básica somente com evidência disponível;
- não cria segundo backend, segunda identidade ou nova Intelligence paralela;
- não toca Treble vendedor nem #36/Gate.

### Lane D — Pós-turno / memória / write-back / Silence

Responsável por:
- investigar o que já existe de memória pós-turno, write-back/dispatch e continuidade/Silence;
- separar o que já funciona do que falta;
- implementar apenas deltas isolados que não conflitem com lanes A/B/C e cuja decisão já esteja congelada;
- não altera o caminho síncrono de resposta do Treble enquanto Lane B trabalha nele;
- se faltar decisão de produto real, retornar a pergunta exata em vez de inventar.

### Lane E — Play / experiência do concierge

Responsável por investigação paralela de:
- NPS por sessão e geral;
- slides/materiais;
- AMA/perguntas sobre conteúdo;
- votação 2027;
- feedback de masterclass/workshop;
- ofertas contextuais Institute/Dash;
- humor como camada de copy, sem inventar fatos.

Primeiro deve localizar a superfície/repo real que entrega o Play. Não criar frontend/backend paralelo se já existir uma superfície aproveitável. Implementação só quando for isolada e não conflitar com Lane C.

## Regras anti-conflito

1. Um componente tem um único dono durante o paralelo.
2. Lane A é dona de #36 e Gate.
3. Lane B é dona do runtime vendedor/Treble.
4. Lane C é dona do runtime concierge/retrieval dessa rota.
5. Lane D não toca o runtime síncrono compartilhado sem coordenação.
6. Lane E não cria uma segunda superfície se o app/web atual puder ser reutilizado.
7. Nenhum lane mergeia por conta própria.
8. Todo lane trabalha sobre branch própria e abre PR draft.
9. Antes do teste final, cada branch traz o `main` mais recente.
10. Divergência material ou decisão de negócio não congelada volta para Adriana; espera técnica/CI/preview não é decisão de negócio.

## Ordem de integração/deploy

```text
A1 #36 Kit Loader
→ A2 Gate
→ B Vendedor/Decisioning/Agent/Treble
→ C Concierge
→ D memória/write-back/Silence
→ E Play/recomendação/experiência
→ E2E Vendedor + Concierge
→ documentação final
```

O trabalho B/C/D/E começa em paralelo antes de A terminar; apenas o merge final respeita essa ordem quando houver dependência real.

## Critério de saída de cada lane

Cada lane deve devolver somente:
- o que já existia e foi reutilizado;
- menor mudança feita;
- branch/PR/HEAD;
- arquivos/componentes tocados;
- testes afetados e resultado;
- dependência concreta ainda pendente;
- qualquer divergência real.

Sem recapitularem investigação antiga e sem abrirem novas frentes.