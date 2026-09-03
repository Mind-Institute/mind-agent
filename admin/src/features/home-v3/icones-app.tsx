import type { IconeAviso } from '@/contracts';

/* ============================================================
   ÍCONES DO APP
   ============================================================
   Os mesmos traços que o participante vê, redesenhados aqui para a
   prévia. Espelham `home/estado.js` na raiz do repositório — o app
   desenha os dele, o painel desenha estes, e a chave (`lugar`, `fone`…)
   é o que viaja entre os dois.

   Mesma linguagem gráfica de lá: traço de 1.8, pontas e junções
   arredondadas, sem preenchimento. Ícone cheio destoaria da interface
   inteira do app. */

const comuns = {
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.8,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
};

const CAMINHOS: Record<IconeAviso, React.ReactNode> = {
  megafone: (
    <>
      <path d="M3 11v2a1 1 0 0 0 1 1h2.5L14 19V5L6.5 10H4a1 1 0 0 0-1 1z" />
      <path d="M17.5 9a4 4 0 0 1 0 6" />
      <path d="M6.5 14.5V19a1.5 1.5 0 0 0 3 0v-3" />
    </>
  ),
  lugar: (
    <>
      <path d="M12 21s7-5.6 7-11a7 7 0 1 0-14 0c0 5.4 7 11 7 11z" />
      <circle cx="12" cy="10" r="2.6" />
    </>
  ),
  relogio: (
    <>
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5.2l3.2 2" />
    </>
  ),
  sino: (
    <>
      <path d="M18 9a6 6 0 1 0-12 0c0 5-2 6.5-2 6.5h16S18 14 18 9z" />
      <path d="M10.5 19a2 2 0 0 0 3 0" />
    </>
  ),
  ingresso: (
    <>
      <path d="M3 8V6a1 1 0 0 1 1-1h16a1 1 0 0 1 1 1v2a2.5 2.5 0 0 0 0 5v3a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1v-3a2.5 2.5 0 0 0 0-5z" />
      <path d="M9.5 5v14" strokeDasharray="2 2.5" />
    </>
  ),
  fone: (
    <>
      <path d="M4 14v-2a8 8 0 0 1 16 0v2" />
      <rect x="2" y="14" width="4.5" height="6" rx="2" />
      <rect x="17.5" y="14" width="4.5" height="6" rx="2" />
    </>
  ),
  agenda: (
    <>
      <rect x="3" y="4.5" width="18" height="16" rx="4" />
      <path d="M8 2.5v4M16 2.5v4M3 10h18" />
    </>
  ),
  alerta: (
    <>
      <path d="M10.3 3.9 2.6 17a2 2 0 0 0 1.7 3h15.4a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z" />
      <path d="M12 9v4.5M12 17.2v.1" />
    </>
  ),
  estrela: <path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z" />,
  carro: (
    <>
      <path d="M4 16.5v-3.6c0-.5.1-1 .4-1.4l2-4.1A2 2 0 0 1 8.2 6.3h7.6a2 2 0 0 1 1.8 1.1l2 4.1c.3.4.4.9.4 1.4v3.6" />
      <path d="M4.6 11.5h14.8" />
      <circle cx="8" cy="17" r="1.8" />
      <circle cx="16" cy="17" r="1.8" />
      <path d="M4 17h2.2M9.8 17h4.4M17.8 17H20" />
    </>
  ),
};

export function IconeDoApp({ nome, className }: { nome: IconeAviso; className?: string }) {
  return (
    <svg {...comuns} className={className} aria-hidden="true">
      {CAMINHOS[nome]}
    </svg>
  );
}
