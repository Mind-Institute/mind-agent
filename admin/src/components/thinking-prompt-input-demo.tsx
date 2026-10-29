import * as React from "react";
import { RotateCcw, Sparkles } from "lucide-react";
import { ThinkingPromptInput } from "@/components/ui/thinking-prompt-input";
import type { ThinkingStatus, ThinkingStep, ThinkingSubmitOptions } from "@/components/ui/thinking-prompt-input";

/* ============================================================================
 * Exemplo de uso do `ThinkingPromptInput`.
 * ============================================================================
 * FICA FORA DE `components/ui/` de propósito: pela convenção do shadcn, que
 * este projeto segue no `components.json`, aquela pasta é de primitivos —
 * peças que outras telas compõem. Um exemplo com relógio, texto de viagem e
 * laço de repetição não é primitivo de nada, e ali ele seria instalado junto
 * com o componente por quem só queria o componente.
 *
 * NADA IMPORTA ESTE ARQUIVO. Ele existe para ver a peça funcionando antes de
 * decidir onde ela entra. Para olhar, aponte uma rota para ele; para
 * descartar, apague o arquivo e nada mais se mexe.
 *
 * O "use client" do original saiu pelo mesmo motivo do componente: aqui é
 * Vite + React 18, sem RSC.
 *
 * As respostas e os passos abaixo são FALSOS, gerados por `setTimeout` nesta
 * página. Não há servidor envolvido, e é por isso que o texto de exemplo diz
 * que os preços são ilustrativos — um exemplo que parece dado real é um
 * exemplo que vira print numa reunião.
 * ==========================================================================*/

const PROMPT = "Plan a 3-day Kyoto trip under $800";
const ANSWER = "Day 1 · Wander through Higashiyama and Gion.\nDay 2 · Fushimi Inari, then a taste of Nishiki Market.\nDay 3 · A slow morning in Arashiyama's bamboo grove.";
const STEPS: ThinkingStep[] = [
  { id: "flights", text: "Checking flight prices…", status: "active" },
  { id: "hotels", text: "Comparing 12 hotels…", status: "active" },
  { id: "budget", text: "Budget check: $742", status: "complete" },
];

type DemoProps = { autoplay?: boolean; loop?: boolean };
type DemoState = { status: ThinkingStatus; prompt: string; value: string; steps: ThinkingStep[]; answer: string; elapsed: number };
const initial = (): DemoState => ({ status: "idle", prompt: "", value: "", steps: [], answer: "", elapsed: 0 });

export default function ThinkingDemo({ autoplay = true, loop = true }: DemoProps) {
  const [state, setState] = React.useState(initial);
  const [think, setThink] = React.useState(true);
  const [motion, setMotion] = React.useState({ ready: false, reduced: true });
  const [run, setRun] = React.useState({ id: 0, source: "auto", prompt: PROMPT, think: true });
  const [paused, setPaused] = React.useState(false);
  const interacted = React.useRef(false);

  React.useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setMotion({ ready: true, reduced: media.matches });
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  React.useEffect(() => {
    if (!motion.ready) return;
    if (run.source === "auto" && (!autoplay || motion.reduced || paused)) {
      if (motion.reduced) setState((previous) => previous.status === "idle" ? previous : initial());
      return;
    }
    const timers: number[] = [];
    let interval = 0;
    const later = (ms: number, callback: () => void) => timers.push(window.setTimeout(callback, ms));
    const example = run.prompt === PROMPT;
    const response = example
      ? ANSWER
      : `This is a local interaction demo.\nYour prompt: "${run.prompt}"\nConnect your own response stream to answer this question.`;
    const progress: ThinkingStep[] = example ? STEPS : [
      { id: "read", text: "Reading your prompt…", status: "active" },
      { id: "prepare", text: "Preparing a sample response…", status: "active" },
      { id: "ready", text: "Sample ready", status: "complete" },
    ];
    const finished = progress.map((step) => ({ ...step, status: "complete" as const }));
    if (motion.reduced) {
      setState({ status: "done", prompt: run.prompt, value: "", steps: run.think ? finished : [], answer: response, elapsed: 0 });
      return;
    }
    const offset = run.source === "auto" ? 1000 : 0;
    if (run.source === "auto") {
      setState(initial());
      const length = PROMPT.length;
      for (let index = 1; index <= length; index++) {
        later(200 + (index / length) * 620, () => setState((previous) => ({ ...previous, value: PROMPT.slice(0, index) })));
      }
    }
    later(offset, () => setState({ status: run.think ? "thinking" : "answering", prompt: run.prompt, value: "", steps: [], answer: "", elapsed: 0 }));
    if (run.think) {
      [750, 1600, 2450].forEach((time, index) => later(offset + time, () => setState((previous) => ({
        ...previous,
        steps: progress.slice(0, index + 1).map((step, position) => ({ ...step, status: position < index ? "complete" : step.status })),
      }))));
      [1, 2, 3].forEach((second) => later(offset + second * 900, () => setState((previous) => ({ ...previous, elapsed: second }))));
    }
    const answerAt = offset + (run.think ? 3000 : 150);
    later(answerAt, () => setState((previous) => ({ ...previous, status: "answering", steps: run.think ? finished : [], elapsed: run.think ? 4 : 0 })));
    later(answerAt + 350, () => {
      let index = 0;
      interval = window.setInterval(() => {
        index += 3;
        const part = response.slice(0, index);
        setState((previous) => ({ ...previous, answer: part }));
        if (index >= response.length) window.clearInterval(interval);
      }, 28);
    });
    later(answerAt + 2300, () => {
      window.clearInterval(interval);
      setState((previous) => ({ ...previous, status: "done", answer: response }));
    });
    if (loop && run.source === "auto") later(7200, () => {
      if (!interacted.current) setRun((previous) => ({ ...previous, id: previous.id + 1 }));
    });
    return () => { timers.forEach((timer) => window.clearTimeout(timer)); window.clearInterval(interval); };
  }, [autoplay, loop, motion.ready, motion.reduced, paused, run]);

  function send(prompt: string, options: ThinkingSubmitOptions) {
    setPaused(false);
    setRun((previous) => ({ id: previous.id + 1, source: "user", prompt, think: options.think }));
  }

  return (
    <div className="flex min-h-screen w-full items-center justify-center bg-background p-5 font-sans text-foreground">
      <div className="w-full max-w-[480px]">
        <header className="mb-4 flex items-center justify-between gap-4">
          <div>
            <div className="mb-2 flex items-center gap-2 text-[10px] font-medium uppercase tracking-[0.2em] text-muted-foreground">
              <Sparkles className="size-3" aria-hidden="true" /> A little thought goes a long way
            </div>
            <h1 className="text-[25px] font-medium leading-tight tracking-tight">Make room for a better answer.</h1>
          </div>
        </header>
        <div className="flex h-[464px] items-end" data-demo-stage>
          <ThinkingPromptInput
            status={state.status}
            prompt={state.prompt}
            value={state.value}
            onValueChange={(value) => {
              interacted.current = true;
              if (run.source === "auto" && state.status === "idle") setPaused(true);
              setState((previous) => ({ ...previous, value }));
            }}
            think={think}
            onThinkChange={(value) => { setPaused(true); setThink(value); }}
            steps={state.steps}
            answer={state.answer}
            elapsedSeconds={state.elapsed}
            onSubmit={send}
            onStop={() => {
              setPaused(true);
              setRun((previous) => ({ ...previous, source: "auto" }));
              setState((previous) => ({ ...initial(), value: previous.prompt }));
            }}
            answerNote={state.prompt === PROMPT ? "Sample itinerary · Prices are illustrative." : undefined}
          />
        </div>
        <footer className="mt-4 flex items-center justify-between gap-3 text-[10px] text-muted-foreground">
          <span>One prompt. A little perspective.</span>
          <button
            type="button"
            onClick={() => { setPaused(false); setRun((previous) => ({ id: previous.id + 1, source: "user", prompt: PROMPT, think: true })); }}
            className="flex items-center gap-1.5 rounded px-1 py-1 outline-none hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring"
          >
            <RotateCcw className="size-3" aria-hidden="true" /> Replay demo
          </button>
        </footer>
      </div>
    </div>
  );
}
