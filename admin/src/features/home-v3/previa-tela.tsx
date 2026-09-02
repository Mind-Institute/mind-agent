import { useState } from 'react';
import { ExternalLink, RotateCw } from 'lucide-react';
import { ROTULO_MOMENTO, type MomentoHome } from '@/contracts';
import { Button } from '@/components/ui/button';

/* ============================================================
   PRÉVIA DA TELA — o app de verdade, dentro de um quadro
   ============================================================
   Aqui NÃO existe uma segunda versão da home. O que aparece no quadro é
   o app do participante, servido pela mesma origem que o painel — `/` e
   `/admin/` são o mesmo worker.

   POR QUE ASSIM, E NÃO REDESENHADO AQUI. O conteúdo das quatro telas
   mora em `home/estado.js`, dentro do app. O painel não importa código
   do chat, por decisão registrada em `admin/vite.config.ts`. Restariam
   duas saídas: copiar os blocos para cá à mão, ou mostrar o app. Cópia à
   mão envelhece — foi exatamente assim que a barra de abas do tour
   passou meses ensinando nomes de menu que o app já não tinha. O quadro
   não tem como divergir: ele É a tela.

   `?momento=` é a porta que o app já abria para isso. Ela semeia a
   escolha no `sessionStorage` da aba e sai da URL. O seletor de momento
   que aparece no topo do app em desenvolvimento NÃO vem junto: aquele é
   travado por hostname (`localhost` ou `?dev=1`), e o painel publicado
   não é nenhum dos dois.

   A prévia não muda o que está no ar. Ver e publicar são dois gestos
   diferentes, e é a página que faz essa separação. */

/** De onde o app é servido.
 *
 *  Em produção, painel e app dividem o worker: `/admin/` e `/`. Daí o
 *  padrão ser a raiz.
 *
 *  Em desenvolvimento o painel roda sozinho na 5174 e `/` é ele mesmo —
 *  apontar o quadro para lá abriria o painel dentro do painel. Por isso
 *  ali a variável é obrigatória, e sem ela a prévia diz o que falta em
 *  vez de mostrar coisa errada. */
function baseDoApp(): string | null {
  const declarada = import.meta.env.VITE_APP_BASE_URL?.trim();
  if (declarada) return declarada.replace(/\/+$/, '') || '/';
  return import.meta.env.DEV ? null : '/';
}

export interface PreviaTelaProps {
  momento: MomentoHome;
}

export function PreviaTela({ momento }: PreviaTelaProps) {
  /* Recarregar é o gesto de "acabei de mexer, quero ver o efeito". Um
     aviso publicado agora só aparece no quadro depois disto — o app lê a
     lista uma vez, na carga. Trocar a `key` remonta o quadro do zero;
     mexer no `src` deixaria a página anterior no histórico do iframe. */
  const [recarga, setRecarga] = useState(0);
  const base = baseDoApp();

  if (!base) {
    return (
      <div className="rounded-xl border border-dashed p-6 text-center">
        <p className="text-sm font-medium">A prévia não abre em desenvolvimento</p>
        <p className="mx-auto mt-1 max-w-md text-xs text-muted-foreground">
          Preencha <code className="font-mono">VITE_APP_BASE_URL</code> em{' '}
          <code className="font-mono">admin/.env.local</code> com o endereço onde o
          app do participante está servido — sem isso, o quadro abriria o próprio
          painel. Em produção não é preciso: os dois vivem na mesma origem.
        </p>
      </div>
    );
  }

  const url = base + (base.endsWith('/') ? '' : '/') + '?momento=' + momento;

  return (
    <div>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <p className="text-xs text-muted-foreground">
          O app de verdade, na tela <strong>{ROTULO_MOMENTO[momento]}</strong>. Não é
          uma reprodução: é a mesma página que o participante abre.
        </p>
        <span className="flex items-center gap-2">
          <Button variant="outline" size="sm" onClick={() => setRecarga((n) => n + 1)}>
            <RotateCw className="mr-2 size-4" />
            Atualizar
          </Button>
          <Button variant="ghost" size="sm" asChild>
            <a href={url} target="_blank" rel="noreferrer">
              <ExternalLink className="mr-2 size-4" />
              Abrir em outra aba
            </a>
          </Button>
        </span>
      </div>

      {/* 390x844 é o iPhone 14/15 sem a barra do navegador — o aparelho mais
          comum entre os participantes e o mais estreito que precisa caber. */}
      <div className="flex justify-center">
        <div
          className="overflow-hidden rounded-[28px] border shadow-sm"
          style={{ width: 390, height: 844, background: '#13131a' }}
        >
          <iframe
            key={momento + ':' + recarga}
            src={url}
            title={'Tela ' + ROTULO_MOMENTO[momento] + ' do app do participante'}
            className="block size-full border-0"
          />
        </div>
      </div>
    </div>
  );
}
