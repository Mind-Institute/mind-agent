/* ============================================================
   PONTE DE DEMONSTRAÇÃO — o painel falando com o app, sem banco
   ============================================================
   O painel e o app do participante são servidos da MESMA ORIGEM: o app
   em `/`, o painel em `/admin/`. Origem igual quer dizer `localStorage`
   compartilhado — e é só disso que esta ponte precisa.

   O QUE ELA É
   Uma forma de ver o módulo Home V3 funcionando de ponta a ponta hoje:
   dispara um aviso aqui, troca de aba, e o app mostra. Serve para
   demonstrar, revisar texto e aprovar comportamento antes de qualquer
   coisa ir para produção.

   O QUE ELA NÃO É
   Disparo. O que se escreve aqui vive no navegador de quem escreveu. No
   celular do participante, nada. Para o aviso sair daqui e chegar lá é
   preciso armazenamento compartilhado de verdade — o Supabase, pelos
   arquivos em `docs/sql/home-v3/`.

   POR QUE NÃO VIRA GAMBIARRA
   O app já lê avisos e momento por duas portas — `definirAvisos()` e
   `definirMomentoDoServidor()`. A ponte entra ATRÁS delas, como último
   recurso, depois da API. No dia em que o banco responder, o payload
   ganha da ponte e isto aqui deixa de ser lido. Apagar é remover a
   chamada; nada mais depende disto.

   O FORMATO É O DO APP, não o do painel: quem converte é quem publica,
   para o app não precisar conhecer o vocabulário do administrativo. */

import type { AvisoHome, EstadoHome, TrocaHome } from '@/contracts';

/** A mesma chave que `app.js` procura. Mudar aqui exige mudar lá. */
const CHAVE = 'mindagent:v1:ponte-demonstracao';

/** O que o app espera receber, já no vocabulário dele. */
type AvisoDoApp = {
  id: string;
  icone: string;
  em: string;
  situacao: string;
  titulo: string;
  resumo: string;
  mensagem: string;
};

export type PonteDemonstracao = {
  avisos: AvisoDoApp[];
  home: { momento: string; modo: string; trocas: { quando: string; momento: string }[] };
  publicadoEm: string;
};

function paraOApp(a: AvisoHome): AvisoDoApp {
  return {
    id: a.id,
    icone: a.icone,
    /* O app ordena e formata a partir deste campo, e ele é ISO local. */
    em: a.disparoEm,
    situacao: a.situacao,
    titulo: a.titulo,
    resumo: a.subtitulo,
    mensagem: a.descricao,
  };
}

/**
 * Publica o que as páginas estão mostrando para o app do participante,
 * no mesmo navegador. Silenciosa por decisão: numa aba anônima, ou com
 * o armazenamento cheio, a demonstração simplesmente não acontece — não
 * é motivo para quebrar a tela de quem está editando.
 */
export function publicarParaOApp(dados: {
  avisos?: AvisoHome[];
  estado?: EstadoHome;
  trocas?: TrocaHome[];
}): void {
  try {
    const anterior = ler();
    const ponte: PonteDemonstracao = {
      avisos: dados.avisos ? dados.avisos.map(paraOApp) : (anterior?.avisos ?? []),
      home: dados.estado
        ? {
            momento: dados.estado.momento,
            modo: dados.estado.modo,
            /* Todas as trocas: quem aplica a regra do horário é o app,
               como faz com os avisos agendados. */
            trocas: (dados.trocas ?? []).map((t) => ({ quando: t.quando, momento: t.momento })),
          }
        : (anterior?.home ?? { momento: 'antes', modo: 'manual', trocas: [] }),
      publicadoEm: new Date().toISOString(),
    };
    window.localStorage.setItem(CHAVE, JSON.stringify(ponte));
  } catch {
    /* aba anônima, cota cheia, storage bloqueado */
  }
}

function ler(): PonteDemonstracao | null {
  try {
    const cru = window.localStorage.getItem(CHAVE);
    return cru ? (JSON.parse(cru) as PonteDemonstracao) : null;
  } catch {
    return null;
  }
}
