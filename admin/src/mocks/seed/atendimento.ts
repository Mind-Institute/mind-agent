/* ============================================================
   SEMENTES DE ATENDIMENTO — conversas, perguntas sem resposta, auditoria
   ============================================================
   Estas três nascem em função de "agora": a métrica "conversas nas
   últimas 24 horas" só significa alguma coisa se as conversas forem
   recentes de verdade. Por isso são FUNÇÕES, não constantes.

   NENHUM DADO PESSOAL REAL. Nomes fictícios, contatos no formato de
   exemplo — e ainda assim a tela mascara tudo antes de mostrar. As
   duas coisas, porque uma sozinha não é garantia. */

import type { Conversa, PerguntaSemResposta, RegistroAuditoria } from '@/contracts';

const HORA = 3600_000;

function menos(agora: number, horas: number): string {
  return new Date(agora - horas * HORA).toISOString();
}

export function conversasSemente(agora: number): Conversa[] {
  return [
    {
      id: 'cnv_001',
      participanteNome: 'Participante Um',
      participanteContato: '+5511900000001',
      canal: 'whatsapp',
      iniciadaEm: menos(agora, 3),
      ultimaAtividadeEm: menos(agora, 2.6),
      totalMensagens: 6,
      assuntos: ['programação', 'reserva'],
      handoff: false,
      status: 'resolvida',
      mensagens: [
        {
          id: 'msg_001',
          autor: 'participante',
          texto: 'oi, a palestra da Amy Edmondson é em qual palco?',
          enviadaEm: menos(agora, 3),
        },
        {
          id: 'msg_002',
          autor: 'agente',
          texto:
            'Oi! 💚 A sessão da Amy Edmondson é na Arena Mind, dia 16 às 14h00. Quer que eu te mostre como chegar?',
          enviadaEm: menos(agora, 2.98),
        },
        {
          id: 'msg_003',
          autor: 'participante',
          texto: 'quero sim',
          enviadaEm: menos(agora, 2.9),
        },
        {
          id: 'msg_004',
          autor: 'agente',
          texto:
            'Do credenciamento, siga em frente pelo corredor central. A Arena Mind é o palco grande ao fundo, à esquerda.',
          enviadaEm: menos(agora, 2.88),
        },
        {
          id: 'msg_005',
          autor: 'participante',
          texto: 'preciso reservar?',
          enviadaEm: menos(agora, 2.7),
        },
        {
          id: 'msg_006',
          autor: 'agente',
          texto:
            'Nessa não. Reserva só nas sessões com vaga limitada — Arena Sextante, workshops e masterclasses. Quem confirma é você, pelo app; eu ainda não consigo agendar no seu lugar.',
          enviadaEm: menos(agora, 2.6),
        },
      ],
      criadoEm: menos(agora, 3),
      atualizadoEm: menos(agora, 2.6),
      atualizadoPor: null,
    },
    {
      id: 'cnv_002',
      participanteNome: 'Participante Dois',
      participanteContato: 'participante.dois@exemplo.com.br',
      canal: 'chat_proprio',
      iniciadaEm: menos(agora, 9),
      ultimaAtividadeEm: menos(agora, 8.4),
      totalMensagens: 4,
      assuntos: ['ingressos', 'preço'],
      handoff: true,
      status: 'handoff',
      mensagens: [
        {
          id: 'msg_101',
          autor: 'participante',
          texto: 'quanto custa o pacote corporativo pra 10 pessoas?',
          enviadaEm: menos(agora, 9),
        },
        {
          id: 'msg_102',
          autor: 'agente',
          texto:
            'O pacote corporativo existe, mas eu não tenho o valor cadastrado aqui. Prefiro te passar para o comercial a chutar um número.',
          enviadaEm: menos(agora, 8.9),
        },
        {
          id: 'msg_103',
          autor: 'participante',
          texto: 'pode ser, meu contato é participante.dois@exemplo.com.br',
          enviadaEm: menos(agora, 8.6),
        },
        {
          id: 'msg_104',
          autor: 'humano',
          texto: 'Oi! Aqui é o Diego, do time comercial. Já te mando a proposta por e-mail.',
          enviadaEm: menos(agora, 8.4),
        },
      ],
      criadoEm: menos(agora, 9),
      atualizadoEm: menos(agora, 8.4),
      atualizadoPor: null,
    },
    {
      id: 'cnv_003',
      participanteNome: null,
      participanteContato: null,
      canal: 'widget',
      iniciadaEm: menos(agora, 20),
      ultimaAtividadeEm: menos(agora, 19.8),
      totalMensagens: 2,
      assuntos: ['estacionamento'],
      handoff: false,
      status: 'abandonada',
      mensagens: [
        {
          id: 'msg_201',
          autor: 'participante',
          texto: 'tem estacionamento no local?',
          enviadaEm: menos(agora, 20),
        },
        {
          id: 'msg_202',
          autor: 'agente',
          texto:
            'Ainda não tenho essa informação cadastrada. Registrei a pergunta para o time responder.',
          enviadaEm: menos(agora, 19.8),
        },
      ],
      criadoEm: menos(agora, 20),
      atualizadoEm: menos(agora, 19.8),
      atualizadoPor: null,
    },
    {
      id: 'cnv_004',
      participanteNome: 'Participante Quatro',
      participanteContato: '+5511900000004',
      canal: 'whatsapp',
      iniciadaEm: menos(agora, 30),
      ultimaAtividadeEm: menos(agora, 29.5),
      totalMensagens: 3,
      assuntos: ['credenciamento'],
      handoff: false,
      status: 'resolvida',
      mensagens: [
        {
          id: 'msg_301',
          autor: 'participante',
          texto: 'que horas abre o credenciamento?',
          enviadaEm: menos(agora, 30),
        },
        {
          id: 'msg_302',
          autor: 'agente',
          texto: 'O credenciamento abre às 8h nos dois dias. A abertura é às 9h, na Arena Mind.',
          enviadaEm: menos(agora, 29.8),
        },
        {
          id: 'msg_303',
          autor: 'participante',
          texto: 'perfeito, obrigado',
          enviadaEm: menos(agora, 29.5),
        },
      ],
      criadoEm: menos(agora, 30),
      atualizadoEm: menos(agora, 29.5),
      atualizadoPor: null,
    },
    {
      id: 'cnv_005',
      participanteNome: 'Participante Cinco',
      participanteContato: 'participante.cinco@exemplo.com.br',
      canal: 'chat_proprio',
      iniciadaEm: menos(agora, 1.2),
      ultimaAtividadeEm: menos(agora, 0.8),
      totalMensagens: 3,
      assuntos: ['acessibilidade'],
      handoff: false,
      status: 'aberta',
      mensagens: [
        {
          id: 'msg_401',
          autor: 'participante',
          texto: 'o Prime Lounge tem acesso por elevador?',
          enviadaEm: menos(agora, 1.2),
        },
        {
          id: 'msg_402',
          autor: 'agente',
          texto:
            'A rota que eu tenho cadastrada para o Prime Lounge é por escada. Não vou afirmar que existe elevador sem ter isso registrado — pedi ao time para confirmar.',
          enviadaEm: menos(agora, 1.0),
        },
        {
          id: 'msg_403',
          autor: 'participante',
          texto: 'ok, aguardo',
          enviadaEm: menos(agora, 0.8),
        },
      ],
      criadoEm: menos(agora, 1.2),
      atualizadoEm: menos(agora, 0.8),
      atualizadoPor: null,
    },
  ];
}

export function perguntasSemente(agora: number): PerguntaSemResposta[] {
  return [
    {
      id: 'psr_001',
      pergunta: 'Tem estacionamento no local? Quanto custa?',
      ocorrencias: 23,
      canal: 'whatsapp',
      ultimaOcorrenciaEm: menos(agora, 2),
      categoriaSugerida: 'Logística',
      responsavel: null,
      status: 'nova',
      conteudoVinculadoId: null,
      criadoEm: menos(agora, 96),
      atualizadoEm: menos(agora, 2),
      atualizadoPor: null,
    },
    {
      id: 'psr_002',
      pergunta: 'O Prime Lounge tem acesso por elevador?',
      ocorrencias: 8,
      canal: 'chat_proprio',
      ultimaOcorrenciaEm: menos(agora, 1),
      categoriaSugerida: 'Acessibilidade',
      responsavel: 'Diego Farias',
      status: 'em_analise',
      conteudoVinculadoId: null,
      criadoEm: menos(agora, 48),
      atualizadoEm: menos(agora, 1),
      atualizadoPor: 'Diego Farias',
    },
    {
      id: 'psr_003',
      pergunta: 'Quanto custa o pacote corporativo para 10 pessoas?',
      ocorrencias: 15,
      canal: 'chat_proprio',
      ultimaOcorrenciaEm: menos(agora, 9),
      categoriaSugerida: 'Ingressos',
      responsavel: 'Bruno Lemos',
      status: 'em_analise',
      conteudoVinculadoId: null,
      criadoEm: menos(agora, 120),
      atualizadoEm: menos(agora, 9),
      atualizadoPor: 'Bruno Lemos',
    },
    {
      id: 'psr_004',
      pergunta: 'A gravação das palestras fica disponível depois?',
      ocorrencias: 31,
      canal: 'whatsapp',
      ultimaOcorrenciaEm: menos(agora, 5),
      categoriaSugerida: 'Conteúdo',
      responsavel: null,
      status: 'nova',
      conteudoVinculadoId: null,
      criadoEm: menos(agora, 200),
      atualizadoEm: menos(agora, 5),
      atualizadoPor: null,
    },
    {
      id: 'psr_005',
      pergunta: 'Posso transferir meu ingresso para outra pessoa?',
      ocorrencias: 12,
      canal: 'widget',
      ultimaOcorrenciaEm: menos(agora, 26),
      categoriaSugerida: 'Ingressos',
      responsavel: 'Carla Nunes',
      status: 'respondida',
      conteudoVinculadoId: 'doc_politica_reembolso',
      criadoEm: menos(agora, 300),
      atualizadoEm: menos(agora, 26),
      atualizadoPor: 'Carla Nunes',
    },
    {
      id: 'psr_006',
      pergunta: 'Vocês vendem camiseta do evento?',
      ocorrencias: 3,
      canal: 'whatsapp',
      ultimaOcorrenciaEm: menos(agora, 60),
      categoriaSugerida: 'Outros',
      responsavel: null,
      status: 'descartada',
      conteudoVinculadoId: null,
      criadoEm: menos(agora, 400),
      atualizadoEm: menos(agora, 60),
      atualizadoPor: 'Carla Nunes',
    },
  ];
}

export function auditoriaSemente(agora: number): RegistroAuditoria[] {
  return [
    {
      id: 'aud_001',
      usuario: 'Ana Ribeiro',
      acao: 'publicar',
      recurso: 'content',
      registroId: 'con_sobre',
      registroRotulo: 'Quem é a Mind',
      antes: { status: 'em_revisao' },
      depois: { status: 'publicado' },
      ocorridoEm: menos(agora, 340),
      requestId: 'req_5f2c1a90',
    },
    {
      id: 'aud_002',
      usuario: 'Bruno Lemos',
      acao: 'atualizar',
      recurso: 'sessions',
      registroId: 'ses_d1-11_30-decidir_sob_press_o_co',
      registroRotulo: 'Decidir sob pressão',
      antes: { inicio: '11:00', fim: '12:00' },
      depois: { inicio: '11:30', fim: '12:30' },
      ocorridoEm: menos(agora, 120),
      requestId: 'req_7b31de04',
    },
    {
      id: 'aud_003',
      usuario: 'Carla Nunes',
      acao: 'arquivar',
      recurso: 'offers',
      registroId: 'ofe_lote1',
      registroRotulo: 'Primeiro lote',
      antes: { ativo: true },
      depois: { ativo: false },
      ocorridoEm: menos(agora, 72),
      requestId: 'req_a09c4412',
    },
    {
      id: 'aud_004',
      usuario: 'Ana Ribeiro',
      acao: 'reindexar',
      recurso: 'documents',
      registroId: 'doc_acessibilidade',
      registroRotulo: 'Guia de acessibilidade do evento',
      antes: { statusIndexacao: 'nao_indexado' },
      depois: { statusIndexacao: 'na_fila' },
      ocorridoEm: menos(agora, 30),
      requestId: 'req_c7710bd2',
    },
    {
      id: 'aud_005',
      usuario: 'Bruno Lemos',
      acao: 'criar',
      recurso: 'content',
      registroId: 'con_produtos',
      registroRotulo: 'Plataformas e produtos',
      antes: null,
      depois: { status: 'rascunho', categoria: 'produtos' },
      ocorridoEm: menos(agora, 190),
      requestId: 'req_1de88a35',
    },
    {
      id: 'aud_006',
      usuario: 'Diego Farias',
      acao: 'login',
      recurso: 'users',
      registroId: 'usr_diego',
      registroRotulo: 'Diego Farias',
      antes: null,
      depois: null,
      ocorridoEm: menos(agora, 12),
      requestId: 'req_31ab7700',
    },
  ];
}
