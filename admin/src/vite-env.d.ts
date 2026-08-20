/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** Raiz das Edge Functions administrativas. Vazio = modo demonstração. */
  readonly VITE_ADMIN_API_BASE_URL?: string;
  /** `mock`, `hybrid` (padrão com API) ou `http`. Ver provider-context. */
  readonly VITE_ADMIN_DATA_MODE?: string;
  /** Projeto Supabase — usado apenas por Supabase Auth, no futuro. */
  readonly VITE_SUPABASE_URL?: string;
  /** Chave publicável (anon). Nunca `service_role`, nunca secret key. */
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare module '*.png' {
  const src: string;
  export default src;
}
