import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const migration = readFileSync(
  new URL("../supabase/migrations/20260904230123_treble_preco_parcelado_e_handoff_com_motivo.sql", import.meta.url),
  "utf8",
);

test("patch do prompt exige versão e hash exatos e prova reversibilidade", () => {
  assert.match(migration, /v_versao <> 2/);
  assert.match(migration, /7668a62d9f01bb98fff3ce06af7d738a5bbfec6b055d13958de8fbebd84a7860/);
  assert.match(migration, /ancora HUMANO nao e unica/);
  assert.match(migration, /replace\(v_depois, v_bloco, v_ancora\) is distinct from v_antes/);
});

test("playbooks B2C e B2B são apenas verificados, nunca atualizados", () => {
  assert.doesNotMatch(migration, /update\s+agentes\.prompts[\s\S]{0,200}playbook_summit_b2[cb]/i);
  assert.match(migration, /playbook B2C foi alterado/);
  assert.match(migration, /playbook B2B foi alterado/);
});

test("regra põe parcela antes do total e impede handoff na troca VIP para Prime", () => {
  assert.match(migration, /O \[categoria\] está 12x R\$\[parcela\] no lote vigente \(R\$\[valor total\]\)/);
  assert.match(migration, /Nunca acione handoff porque a pessoa mudou de VIP para Prime/);
  assert.match(migration, /handoff_reason=null/);
});
