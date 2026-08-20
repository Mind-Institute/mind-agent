/* ============================================================
   VISÃO GERAL — cálculo a partir do banco em memória
   ============================================================
   Os números saem do mesmo banco que as listagens, com as mesmas
   regras de `src/lib/pendencias.ts`. Clicar no cartão leva à lista que
   explica o número: se a visão geral diz "2 sessões sem espaço", a
   listagem filtrada mostra exatamente essas duas. */

import type { GrupoPendencia, ItemPendencia, ResumoPainel } from '@/contracts';
import {
  alertasDaOferta,
  camposFaltantesDaSessao,
  camposFaltantesDoEspaco,
  camposFaltantesDoPalestrante,
  ehPalco,
} from '@/lib/pendencias';
import type { BancoMock } from './db';

const AMOSTRA = 5;

function grupo(
  categoria: GrupoPendencia['categoria'],
  titulo: string,
  descricao: string,
  destino: string,
  itens: ItemPendencia[],
): GrupoPendencia {
  return {
    categoria,
    titulo,
    descricao,
    total: itens.length,
    itens: itens.slice(0, AMOSTRA),
    destino,
  };
}

export function montarResumoPainel(banco: BancoMock): ResumoPainel {
  const agora = Date.now();
  const hoje = new Date(agora).toISOString().slice(0, 10);
  const umDiaAtras = agora - 24 * 3600_000;

  const sessoesAtivas = banco.sessions.filter((s) => s.status !== 'arquivado');
  const palestrantesAtivos = banco.speakers.filter((p) => p.status !== 'arquivado');
  const espacosAtivos = banco.spaces.filter((e) => e.ativo);
  const estandesAtivos = banco.booths.filter((e) => e.ativo);
  const ofertasAtivas = banco.offers.filter((o) => o.ativo && o.dataFim >= hoje);
  const documentosPublicados = banco.documents.filter(
    (d) => d.ativo && d.statusIndexacao === 'indexado',
  );
  const documentosAguardando = banco.documents.filter(
    (d) => d.ativo && (d.statusIndexacao === 'na_fila' || d.statusIndexacao === 'indexando'),
  );
  const perguntasAbertas = banco.unanswered.filter(
    (p) => p.status === 'nova' || p.status === 'em_analise',
  );
  const conversas24h = banco.conversations.filter(
    (c) => new Date(c.ultimaAtividadeEm).getTime() >= umDiaAtras,
  );

  /* ---------------------------------------------------------------- */
  /* Pendências                                                       */
  /* ---------------------------------------------------------------- */
  const sessoesSemEspaco = sessoesAtivas
    .filter((s) => !s.espacoId)
    .map<ItemPendencia>((s) => ({
      id: s.id,
      rotulo: `${s.titulo} · ${s.dia} ${s.inicio}`,
      destino: `/programacao/${s.id}`,
    }));

  const sessoesSemPalestrante = sessoesAtivas
    .filter((s) => s.palestranteIds.length === 0 && !s.quemTexto.trim())
    .map<ItemPendencia>((s) => ({
      id: s.id,
      rotulo: `${s.titulo} · ${s.dia} ${s.inicio}`,
      destino: `/programacao/${s.id}`,
    }));

  const espacosSemLocalizacao = espacosAtivos
    .filter((e) => !e.comoChegar.trim())
    .map<ItemPendencia>((e) => ({ id: e.id, rotulo: e.nome, destino: `/espacos/${e.id}` }));

  const palcosSemAlias = espacosAtivos
    .filter((e) => ehPalco(e) && e.aliases.length === 0)
    .map<ItemPendencia>((e) => ({ id: e.id, rotulo: e.nome, destino: `/espacos/${e.id}` }));

  const ofertasSemCheckout = banco.offers
    .filter((o) => o.ativo && !o.checkoutUrl.trim())
    .map<ItemPendencia>((o) => ({
      id: o.id,
      rotulo: `${o.codigo} · ${o.nome}`,
      destino: `/ofertas/${o.id}`,
    }));

  const documentosSemIndexacao = banco.documents
    .filter((d) => d.ativo && (d.statusIndexacao === 'nao_indexado' || d.statusIndexacao === 'erro'))
    .map<ItemPendencia>((d) => ({ id: d.id, rotulo: d.titulo, destino: `/documentos/${d.id}` }));

  const conteudoEmRascunho = [
    ...banco.content
      .filter((c) => c.status === 'rascunho' || c.status === 'em_revisao')
      .map<ItemPendencia>((c) => ({
        id: c.id,
        rotulo: `Conteúdo · ${c.titulo}`,
        destino: `/conteudo/${c.id}`,
      })),
    ...sessoesAtivas
      .filter((s) => s.status === 'rascunho' || s.status === 'em_revisao')
      .map<ItemPendencia>((s) => ({
        id: s.id,
        rotulo: `Sessão · ${s.titulo}`,
        destino: `/programacao/${s.id}`,
      })),
    ...palestrantesAtivos
      .filter((p) => p.status === 'rascunho' || p.status === 'em_revisao')
      .map<ItemPendencia>((p) => ({
        id: p.id,
        rotulo: `Palestrante · ${p.nome}`,
        destino: `/palestrantes/${p.id}`,
      })),
  ];

  const pendencias: GrupoPendencia[] = [
    grupo(
      'sessoes_sem_espaco',
      'Sessões sem espaço',
      'O agente não consegue responder "onde fica".',
      '/programacao?espacoId=null',
      sessoesSemEspaco,
    ),
    grupo(
      'sessoes_sem_palestrante',
      'Sessões sem palestrante',
      'A grade mostra o horário, mas não quem fala.',
      '/programacao',
      sessoesSemPalestrante,
    ),
    grupo(
      'espacos_sem_localizacao',
      'Espaços sem instrução de localização',
      'Sem "como chegar" o agente só sabe o nome do lugar.',
      '/espacos',
      espacosSemLocalizacao,
    ),
    grupo(
      'palcos_sem_alias',
      'Palcos sem aliases',
      'Quem diz "palco principal" não é entendido.',
      '/espacos',
      palcosSemAlias,
    ),
    grupo(
      'ofertas_sem_checkout',
      'Ofertas sem checkout',
      'A oferta aparece, mas ninguém consegue comprar.',
      '/ofertas',
      ofertasSemCheckout,
    ),
    grupo(
      'documentos_sem_indexacao',
      'Documentos sem indexação',
      'O documento existe e o agente não enxerga.',
      '/documentos',
      documentosSemIndexacao,
    ),
    grupo(
      'conteudo_em_rascunho',
      'Conteúdo em rascunho',
      'Escrito, não publicado — fora do ar para o participante.',
      '/conteudo',
      conteudoEmRascunho,
    ),
  ];

  /* ---------------------------------------------------------------- */
  /* Alertas de dados incompletos                                     */
  /* ---------------------------------------------------------------- */
  const sessoesIncompletas = sessoesAtivas.filter((s) => camposFaltantesDaSessao(s).length > 0);
  const espacosIncompletos = espacosAtivos.filter((e) => camposFaltantesDoEspaco(e).length > 0);
  const palestrantesIncompletos = palestrantesAtivos.filter(
    (p) => camposFaltantesDoPalestrante(p).length > 0,
  );
  const ofertasComAlerta = banco.offers.filter(
    (o) => o.ativo && alertasDaOferta(o, hoje).length > 0,
  );
  const totalIncompletos =
    sessoesIncompletas.length +
    espacosIncompletos.length +
    palestrantesIncompletos.length +
    ofertasComAlerta.length;

  const evento = banco.event[0];
  const alertas: ResumoPainel['alertas'] = [];

  if (evento && evento.locaisCandidatos.length > 1) {
    alertas.push({
      id: 'alerta_local_evento',
      nivel: 'atencao',
      titulo: 'Local do evento em divergência',
      descricao:
        evento.locaisCandidatos.map((c) => `"${c.valor}" (${c.origem})`).join(' vs ') +
        '. O painel não escolhe entre os dois — alguém precisa confirmar qual é o correto.',
      destino: '/evento',
    });
  }

  if (documentosSemIndexacao.length > 0) {
    alertas.push({
      id: 'alerta_documentos',
      nivel: 'atencao',
      titulo: `${documentosSemIndexacao.length} documento(s) fora do índice`,
      descricao: 'Enquanto não forem indexados, o agente responde como se eles não existissem.',
      destino: '/documentos',
    });
  }

  if (palcosSemAlias.length > 0) {
    alertas.push({
      id: 'alerta_aliases',
      nivel: 'atencao',
      titulo: `${palcosSemAlias.length} palco(s) sem alias`,
      descricao: 'Participante que usa apelido do palco não é entendido pelo agente.',
      destino: '/espacos',
    });
  }

  return {
    geradoEm: new Date(agora).toISOString(),
    metricas: [
      {
        chave: 'sessoes',
        rotulo: 'Sessões',
        valor: sessoesAtivas.length,
        destino: '/programacao',
        detalhe: 'na programação ativa',
      },
      {
        chave: 'palestrantes',
        rotulo: 'Palestrantes',
        valor: palestrantesAtivos.length,
        destino: '/palestrantes',
      },
      { chave: 'espacos', rotulo: 'Espaços cadastrados', valor: espacosAtivos.length, destino: '/espacos' },
      { chave: 'estandes', rotulo: 'Estandes cadastrados', valor: estandesAtivos.length, destino: '/estandes' },
      {
        chave: 'ofertas',
        rotulo: 'Ofertas ativas',
        valor: ofertasAtivas.length,
        destino: '/ofertas',
        detalhe: 'vigentes hoje',
      },
      {
        chave: 'documentos_publicados',
        rotulo: 'Documentos publicados',
        valor: documentosPublicados.length,
        destino: '/documentos?statusIndexacao=indexado',
      },
      {
        chave: 'documentos_aguardando',
        rotulo: 'Aguardando indexação',
        valor: documentosAguardando.length,
        destino: '/documentos?statusIndexacao=na_fila',
        tom: documentosAguardando.length > 0 ? 'atencao' : 'neutro',
      },
      {
        chave: 'perguntas',
        rotulo: 'Perguntas sem resposta',
        valor: perguntasAbertas.length,
        destino: '/perguntas',
        tom: perguntasAbertas.length > 0 ? 'atencao' : 'neutro',
      },
      {
        chave: 'conversas_24h',
        rotulo: 'Conversas (24 h)',
        valor: conversas24h.length,
        destino: '/conversas',
      },
      {
        chave: 'dados_incompletos',
        rotulo: 'Alertas de dados incompletos',
        valor: totalIncompletos,
        destino: '/programacao',
        tom: totalIncompletos > 0 ? 'atencao' : 'neutro',
        detalhe: `${sessoesIncompletas.length} sessões · ${espacosIncompletos.length} espaços · ${palestrantesIncompletos.length} palestrantes · ${ofertasComAlerta.length} ofertas`,
      },
    ],
    pendencias,
    alertas,
  };
}
