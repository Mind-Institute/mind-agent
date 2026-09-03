export type ContactFields = {
  firstname: string;
  lastname: string;
  email: string;
  phone: string;
  company: string;
  jobtitle: string;
};

export type ContactPlan = {
  fields: ContactFields | null;
  missing: string[];
  blockedReason: string | null;
};

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function record(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export function contactFromPersonFacts(facts: unknown): ContactPlan {
  const root = record(facts);
  const profile = record(root.perfil);
  const conflicts = Array.isArray(root.conflitos_perfil) ? root.conflitos_perfil : [];
  if (conflicts.some((item) => {
    const field = text(record(item).campo);
    return ["primeiro_nome", "sobrenome", "empresa", "cargo"].includes(field);
  })) {
    return { fields: null, missing: [], blockedReason: "conflito_perfil_contato" };
  }

  const identifiers = Array.isArray(root.identificadores)
    ? root.identificadores.map(record)
    : [];
  const identifiersFor = (channel: string) => [...new Set(identifiers
    .filter((item) => text(item.canal) === channel)
    .map((item) => text(item.identificador))
    .filter(Boolean))];
  const emails = identifiersFor("email");
  const phones = identifiersFor("whatsapp");
  if (emails.length > 1 || phones.length > 1) {
    return { fields: null, missing: [], blockedReason: "identificador_contato_ambiguo" };
  }

  const values: ContactFields = {
    firstname: text(profile.primeiro_nome),
    lastname: text(profile.sobrenome),
    email: emails[0] ?? "",
    phone: phones[0] ?? "",
    company: text(profile.empresa),
    jobtitle: text(profile.cargo),
  };
  const missing = Object.entries(values).filter(([, value]) => !value).map(([key]) => key);
  return {
    fields: missing.length === 0 ? values : null,
    missing,
    blockedReason: missing.length === 0 ? null : "cadastro_contato_incompleto",
  };
}

export function contactEnrichment(
  source: ContactFields,
  current: Record<string, unknown>,
): Record<string, string> {
  return Object.fromEntries(Object.entries(source).filter(([property, value]) =>
    value.length > 0 && !text(current[property])
  ));
}
