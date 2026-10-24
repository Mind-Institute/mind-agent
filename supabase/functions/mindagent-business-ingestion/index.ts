import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const VERSION = "1.0.0";
const MAX_SECTION_CHARS = 140_000;

function readKey(name: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", fallback: string) {
  const raw = Deno.env.get(name);
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      if (typeof parsed.default === "string") return parsed.default;
      const first = Object.values(parsed).find((v) => typeof v === "string");
      if (typeof first === "string") return first;
    } catch { /* fallback */ }
  }
  return Deno.env.get(fallback) ?? "";
}

function cors(req: Request) {
  const origin = req.headers.get("Origin");
  const worker = /^https:\/\/(?:[a-z0-9][a-z0-9-]*-)?mind-agent\.adriana-3eb\.workers\.dev$/;
  const local = new Set(["http://localhost:5174","http://127.0.0.1:5174"]);
  const configured = (Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "").split(",").map((x) => x.trim()).filter(Boolean);
  const allowed = !origin || worker.test(origin) || local.has(origin) || configured.includes(origin);
  return {
    "Access-Control-Allow-Origin": allowed && origin ? origin : "null",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Vary": "Origin",
  };
}
function json(req: Request, status: number, body: unknown, requestId: string) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(req), "Content-Type":"application/json; charset=utf-8", "Cache-Control":"no-store", "X-Request-Id":requestId },
  });
}
function uuid(v: unknown): v is string {
  return typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
}
function obj(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
}
function arr(v: unknown): unknown[] { return Array.isArray(v) ? v : []; }
function text(v: unknown, max=20_000) { return typeof v === "string" ? v.trim().slice(0,max) : ""; }
function num(v: unknown, fallback: number|null=null) {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}
function stringArray(v: unknown) {
  return arr(v).filter((x): x is string => typeof x === "string").map((x) => x.trim()).filter(Boolean);
}
function extractOutput(payload: Record<string, unknown>) {
  if (typeof payload.output_text === "string") return payload.output_text;
  for (const item of arr(payload.output)) {
    const io = obj(item);
    for (const part of arr(io.content)) {
      const po = obj(part);
      if (po.type === "output_text" && typeof po.text === "string") return po.text;
    }
  }
  return "";
}

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  if (req.method === "OPTIONS") return new Response(null,{status:204,headers:cors(req)});
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean);
  if (req.method === "GET" && parts.at(-1) === "health") {
    return json(req,200,{ok:true,service:"mindagent-business-ingestion",version:VERSION},requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const pub = readKey("SUPABASE_PUBLISHABLE_KEYS","SUPABASE_ANON_KEY");
  const secret = readKey("SUPABASE_SECRET_KEYS","SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !pub || !secret) return json(req,503,{ok:false,error:"service_not_configured"},requestId);

  const bearer = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!bearer) return json(req,401,{ok:false,error:"missing_session"},requestId);

  const publicClient = createClient(supabaseUrl,pub,{auth:{persistSession:false,autoRefreshToken:false}});
  const admin = createClient(supabaseUrl,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const { data:userData, error:userError } = await publicClient.auth.getUser(bearer);
  if (userError || !userData.user) return json(req,401,{ok:false,error:"invalid_session"},requestId);
  const { data:access } = await admin.from("mind_admin_users").select("active,role").eq("user_id",userData.user.id).maybeSingle();
  if (!access?.active) return json(req,403,{ok:false,error:"forbidden"},requestId);

  const openAiKey = Deno.env.get("OPENAI_API_KEY") ?? "";
  const bs = admin.schema("business_strategy");

  async function agentConfig(agentKey: string) {
    const { data,error } = await bs.from("ingestion_agent_configs").select("*").eq("agent_key",agentKey).eq("active",true).single();
    if (error || !data) throw new Error("agent_config_missing:"+agentKey);
    return data as Record<string,unknown>;
  }
  async function callAgent(agentKey: string, input: unknown, maxTokens=12000) {
    if (!openAiKey) throw new Error("openai_not_configured");
    const cfg = await agentConfig(agentKey);
    const model = String(cfg.model ?? "");
    const instructions = String(cfg.instructions ?? "");
    const effort = String(cfg.reasoning_effort ?? "medium");
    const r = await fetch("https://api.openai.com/v1/responses",{
      method:"POST",
      headers:{"Authorization":`Bearer ${openAiKey}`,"Content-Type":"application/json"},
      body:JSON.stringify({
        model,
        instructions,
        input:[{role:"user",content:"Responda somente com JSON válido.\n"+JSON.stringify(input)}],
        reasoning:{effort},
        text:{format:{type:"json_object"}},
        max_output_tokens:maxTokens,
        store:false,
      }),
    });
    if (!r.ok) throw new Error("openai_"+r.status+":"+(await r.text()).slice(0,300));
    const payload = await r.json() as Record<string,unknown>;
    const raw = extractOutput(payload);
    return { cfg, data: JSON.parse(raw) as Record<string,unknown> };
  }
  async function stageStart(runId:string,sectionId:string|null,stage:string,agentKey:string) {
    const cfg = await agentConfig(agentKey);
    const { data,error } = await bs.from("ingestion_stage_runs").insert({
      run_id:runId,source_section_id:sectionId,stage,agent_key:agentKey,status:"running",
      model:cfg.model ?? null,prompt_version:cfg.prompt_version ?? null,started_at:new Date().toISOString(),
    }).select("*").single();
    if (error) throw error;
    return data as Record<string,unknown>;
  }
  async function stageDone(id:string,summary:string,metrics:Record<string,unknown>={}) {
    await bs.from("ingestion_stage_runs").update({
      status:"completed",output_summary:summary,metrics,completed_at:new Date().toISOString(),
    }).eq("id",id);
  }
  async function stageFail(id:string,e:unknown) {
    await bs.from("ingestion_stage_runs").update({
      status:"failed",error:e instanceof Error?e.message:String(e),completed_at:new Date().toISOString(),
    }).eq("id",id);
  }
  async function getRun(runId:string) {
    const {data,error}=await bs.from("ingestion_runs").select("*").eq("id",runId).single();
    if(error||!data) throw new Error("run_not_found");
    return data as Record<string,unknown>;
  }

  const iAdmin = parts.lastIndexOf("admin");
  const resource = iAdmin >= 0 ? parts[iAdmin+1] : undefined;
  const id = iAdmin >= 0 ? parts[iAdmin+2] : undefined;
  const action = iAdmin >= 0 ? parts[iAdmin+3] : undefined;

  try {
    if (resource === "agents" && req.method === "GET") {
      const {data,error}=await bs.from("ingestion_agent_configs").select("*").order("created_at");
      if(error) throw error;
      return json(req,200,{items:data ?? []},requestId);
    }

    if (resource !== "runs") return json(req,404,{ok:false,error:"not_found"},requestId);

    if (!id && req.method === "GET") {
      const {data,error}=await bs.from("ingestion_runs")
        .select("*,source:sources(id,title,authors,validation_status)")
        .order("created_at",{ascending:false}).limit(100);
      if(error) throw error;
      return json(req,200,{items:data ?? []},requestId);
    }

    if (!id && req.method === "POST") {
      const body=obj(await req.json().catch(()=>({})));
      if(!uuid(body.source_id)) return json(req,422,{ok:false,error:"invalid_source_id"},requestId);
      const {data:source,error:sourceError}=await bs.from("sources").select("id,title").eq("id",body.source_id).single();
      if(sourceError||!source) return json(req,404,{ok:false,error:"source_not_found"},requestId);
      const {data,error}=await bs.from("ingestion_runs").insert({
        source_id:body.source_id,status:"created",current_stage:"orchestration",
        requested_by:userData.user.id,started_at:new Date().toISOString(),
        metadata:{source_title:source.title},
      }).select("*").single();
      if(error) throw error;
      return json(req,201,{run:data},requestId);
    }

    if (!uuid(id)) return json(req,404,{ok:false,error:"run_not_found"},requestId);

    if (!action && req.method === "GET") {
      const run=await getRun(id);
      const [{data:stages},{data:candidates},{data:findings},{data:rels},{data:links}] = await Promise.all([
        bs.from("ingestion_stage_runs").select("*").eq("run_id",id).order("created_at"),
        bs.from("extraction_candidates").select("id,provisional_name,family,object_type,candidate_status,source_section_id,canonical_object_id").eq("run_id",id).order("created_at"),
        bs.from("ingestion_qa_findings").select("*").eq("run_id",id).order("created_at"),
        bs.from("candidate_relationships").select("*").eq("run_id",id),
        bs.from("candidate_job_links").select("*").eq("run_id",id),
      ]);
      return json(req,200,{run,stages:stages??[],candidates:candidates??[],findings:findings??[],relationships:rels??[],job_links:links??[]},requestId);
    }

    if (action === "extract-section" && req.method === "POST") {
      const run=await getRun(id);
      if (["published","ready_to_publish"].includes(String(run.status))) return json(req,409,{ok:false,error:"run_closed"},requestId);
      const body=obj(await req.json().catch(()=>({})));
      if(!uuid(body.section_id)) return json(req,422,{ok:false,error:"invalid_section_id"},requestId);
      const sectionText=text(body.text,MAX_SECTION_CHARS);
      if(sectionText.length<50) return json(req,422,{ok:false,error:"section_text_too_short"},requestId);
      const {data:section,error:sectionError}=await bs.from("source_sections").select("*").eq("id",body.section_id).eq("source_id",run.source_id).single();
      if(sectionError||!section) return json(req,404,{ok:false,error:"section_not_found"},requestId);

      await bs.from("ingestion_runs").update({status:"extracting",current_stage:"extracting",updated_at:new Date().toISOString()}).eq("id",id);
      const exStage=await stageStart(id,String(body.section_id),"extracting","source_extractor");
      try {
        const extraction=await callAgent("source_extractor",{
          task:"Extract high-recall knowledge candidates from this section. Do not normalize against other sections.",
          section:{id:section.id,title:section.title,number:section.section_number,page_start:section.page_start,page_end:section.page_end},
          required_output:{
            candidates:[{
              provisional_name:"string",family:"string",object_type:"string",summary:"string",scope:"string|null",
              conditions:["string"],limitations:["string"],epistemic_status:"string|null",portability:"string|null",
              domain_scope:["string"],level_of_application:["string"],topics:["string"],
              structured_payload:{components:["string"],steps:["string"],rules:["string"],variables:["string"],notes:["string"]},
              extraction_confidence:"0..1",
              groundings:[{role:"definition|evidence|example|implementation|limitation|extension",locator:"string|null",page_start:"number|null",page_end:"number|null",summary:"string",confidence:"0..1"}]
            }]
          },
          text:sectionText,
        },14000);
        const created:Record<string,unknown>[]=[];
        for(const raw of arr(extraction.data.candidates)){
          const c=obj(raw);
          const name=text(c.provisional_name,300); const summary=text(c.summary,4000);
          if(!name||!summary) continue;
          const {data:row,error}=await bs.from("extraction_candidates").insert({
            run_id:id,source_id:run.source_id,source_section_id:section.id,created_by_stage_run_id:exStage.id,
            provisional_name:name,family:text(c.family,100)||"KNOWLEDGE",object_type:text(c.object_type,120)||"concept",
            summary,scope:text(c.scope,4000)||null,conditions:arr(c.conditions),limitations:arr(c.limitations),
            epistemic_status:text(c.epistemic_status,120)||null,portability:text(c.portability,120)||null,
            domain_scope:stringArray(c.domain_scope),level_of_application:stringArray(c.level_of_application),
            topics:stringArray(c.topics),structured_payload:obj(c.structured_payload),
            extraction_confidence:num(c.extraction_confidence,0.5),candidate_status:"extracted",
          }).select("*").single();
          if(error) throw error;
          created.push(row);
          for(const gRaw of arr(c.groundings)){
            const g=obj(gRaw);
            await bs.from("candidate_groundings").insert({
              candidate_id:row.id,source_id:run.source_id,section_id:section.id,
              grounding_role:text(g.role,80)||"definition",locator:text(g.locator,500)||null,
              page_start:num(g.page_start),page_end:num(g.page_end),grounding_summary:text(g.summary,3000)||summary,
              fidelity_status:"pending",fidelity_confidence:num(g.confidence,0.5),
            });
          }
        }
        await stageDone(String(exStage.id),`${created.length} candidatos extraídos`,{candidates:created.length});

        const reviewStage=await stageStart(id,String(body.section_id),"grounding_review","grounding_reviewer");
        try {
          const review=await callAgent("grounding_reviewer",{
            task:"Verify every candidate against the original section. Return one review per candidate id.",
            required_output:{reviews:[{
              candidate_id:"uuid",verdict:"verified|rejected|needs_review",fidelity_confidence:"0..1",reviewer_note:"string",
              corrections:{summary:"string|null",scope:"string|null",conditions:["string"],limitations:["string"],epistemic_status:"string|null",portability:"string|null"},
              groundings:[{role:"definition|evidence|example|implementation|limitation|extension",locator:"string|null",page_start:"number|null",page_end:"number|null",summary:"string",confidence:"0..1"}]
            }]},
            candidates:created.map((c)=>({id:c.id,name:c.provisional_name,summary:c.summary,scope:c.scope,conditions:c.conditions,limitations:c.limitations,epistemic_status:c.epistemic_status})),
            section:{id:section.id,title:section.title,page_start:section.page_start,page_end:section.page_end},
            text:sectionText,
          },12000);
          let verified=0,rejected=0,needsReview=0;
          for(const raw of arr(review.data.reviews)){
            const rv=obj(raw); if(!uuid(rv.candidate_id)) continue;
            const verdict=text(rv.verdict,30);
            const status=verdict==="verified"?"grounding_verified":verdict==="rejected"?"grounding_rejected":"extracted";
            if(verdict==="verified") verified++; else if(verdict==="rejected") rejected++; else needsReview++;
            const corrections=obj(rv.corrections);
            const patch:Record<string,unknown>={candidate_status:status,updated_at:new Date().toISOString()};
            if(text(corrections.summary,4000)) patch.summary=text(corrections.summary,4000);
            if("scope" in corrections) patch.scope=text(corrections.scope,4000)||null;
            if(Array.isArray(corrections.conditions)) patch.conditions=corrections.conditions;
            if(Array.isArray(corrections.limitations)) patch.limitations=corrections.limitations;
            if("epistemic_status" in corrections) patch.epistemic_status=text(corrections.epistemic_status,120)||null;
            if("portability" in corrections) patch.portability=text(corrections.portability,120)||null;
            await bs.from("extraction_candidates").update(patch).eq("id",rv.candidate_id).eq("run_id",id);
            await bs.from("candidate_groundings").delete().eq("candidate_id",rv.candidate_id);
            for(const gRaw of arr(rv.groundings)){
              const g=obj(gRaw);
              await bs.from("candidate_groundings").insert({
                candidate_id:rv.candidate_id,source_id:run.source_id,section_id:section.id,
                grounding_role:text(g.role,80)||"definition",locator:text(g.locator,500)||null,
                page_start:num(g.page_start),page_end:num(g.page_end),grounding_summary:text(g.summary,3000)||"Grounding revisado",
                fidelity_status:verdict==="verified"?"verified":verdict==="rejected"?"rejected":"needs_review",
                fidelity_confidence:num(g.confidence,num(rv.fidelity_confidence,0.5)),
                reviewer_stage_run_id:reviewStage.id,reviewer_note:text(rv.reviewer_note,2000)||null,
              });
            }
          }
          await bs.from("source_sections").update({processing_status:"processed",updated_at:new Date().toISOString()}).eq("id",section.id);
          await stageDone(String(reviewStage.id),`${verified} verificados, ${rejected} rejeitados, ${needsReview} para revisão`,{verified,rejected,needs_review:needsReview});
          return json(req,200,{ok:true,section_id:section.id,candidates:created.length,verified,rejected,needs_review:needsReview},requestId);
        } catch(e){ await stageFail(String(reviewStage.id),e); throw e; }
      } catch(e){ await stageFail(String(exStage.id),e); throw e; }
    }

    if (action === "finalize" && req.method === "POST") {
      const run=await getRun(id);
      await bs.from("ingestion_runs").update({status:"normalizing_graph",current_stage:"normalizing_graph",updated_at:new Date().toISOString()}).eq("id",id);
      const {data:candidates}=await bs.from("extraction_candidates").select("*").eq("run_id",id).eq("candidate_status","grounding_verified").order("created_at");
      const verified=(candidates??[]) as Record<string,unknown>[];
      if(verified.length===0) return json(req,422,{ok:false,error:"no_verified_candidates"},requestId);
      if(verified.length>350) return json(req,422,{ok:false,error:"too_many_candidates_for_v1",count:verified.length},requestId);

      const normStage=await stageStart(id,null,"normalizing_graph","semantic_normalizer");
      try {
        const normalized=await callAgent("semantic_normalizer",{
          task:"Normalize the full book only now. Return a decision for every verified candidate. Keep source-specific authorship. Relationships must point to representative candidate ids.",
          required_output:{
            decisions:[{candidate_id:"uuid",action:"keep|merge|discard",merge_into_candidate_id:"uuid|null",canonical_name:"string|null",family:"string|null",object_type:"string|null",summary:"string|null",scope:"string|null",conditions:["string"],limitations:["string"],epistemic_status:"string|null",portability:"string|null",domain_scope:["string"],level_of_application:["string"],topics:["string"],structured_payload:{components:["string"],steps:["string"],rules:["string"],variables:["string"],notes:["string"]}}],
            relationships:[{from_candidate_id:"uuid",relationship_type:"string",to_candidate_id:"uuid",summary:"string",confidence:"0..1"}]
          },
          candidates:verified.map((c)=>({id:c.id,name:c.provisional_name,family:c.family,type:c.object_type,summary:c.summary,scope:c.scope,conditions:c.conditions,limitations:c.limitations,epistemic_status:c.epistemic_status,portability:c.portability,topics:c.topics})),
        },24000);
        for(const raw of arr(normalized.data.decisions)){
          const d=obj(raw); if(!uuid(d.candidate_id)) continue;
          const actionName=text(d.action,20);
          if(actionName==="merge" && uuid(d.merge_into_candidate_id)){
            await bs.from("extraction_candidates").update({candidate_status:"merged",merged_into_candidate_id:d.merge_into_candidate_id,updated_at:new Date().toISOString()}).eq("id",d.candidate_id).eq("run_id",id);
            continue;
          }
          if(actionName==="discard"){
            await bs.from("extraction_candidates").update({candidate_status:"discarded",updated_at:new Date().toISOString()}).eq("id",d.candidate_id).eq("run_id",id);
            continue;
          }
          const patch:Record<string,unknown>={candidate_status:"normalized",updated_at:new Date().toISOString()};
          if(text(d.canonical_name,300)) patch.provisional_name=text(d.canonical_name,300);
          for(const [src,dst,max] of [["family","family",100],["object_type","object_type",120],["summary","summary",4000],["scope","scope",4000],["epistemic_status","epistemic_status",120],["portability","portability",120]] as const){
            if(src in d) patch[dst]=text(d[src],max)||null;
          }
          if(Array.isArray(d.conditions)) patch.conditions=d.conditions;
          if(Array.isArray(d.limitations)) patch.limitations=d.limitations;
          if(Array.isArray(d.domain_scope)) patch.domain_scope=stringArray(d.domain_scope);
          if(Array.isArray(d.level_of_application)) patch.level_of_application=stringArray(d.level_of_application);
          if(Array.isArray(d.topics)) patch.topics=stringArray(d.topics);
          if(d.structured_payload) patch.structured_payload=obj(d.structured_payload);
          await bs.from("extraction_candidates").update(patch).eq("id",d.candidate_id).eq("run_id",id);
        }
        await bs.from("candidate_relationships").delete().eq("run_id",id);
        let relCount=0;
        for(const raw of arr(normalized.data.relationships)){
          const rr=obj(raw);
          if(!uuid(rr.from_candidate_id)||!uuid(rr.to_candidate_id)||rr.from_candidate_id===rr.to_candidate_id) continue;
          const {error}=await bs.from("candidate_relationships").upsert({
            run_id:id,from_candidate_id:rr.from_candidate_id,relationship_type:text(rr.relationship_type,120)||"related_to",
            to_candidate_id:rr.to_candidate_id,relationship_summary:text(rr.summary,2000)||null,
            confidence:num(rr.confidence,0.7),validation_status:"proposed",created_by_stage_run_id:normStage.id,
          },{onConflict:"from_candidate_id,relationship_type,to_candidate_id"});
          if(!error) relCount++;
        }
        await stageDone(String(normStage.id),"Normalização full-book concluída",{verified_candidates:verified.length,relationships:relCount});
      } catch(e){ await stageFail(String(normStage.id),e); throw e; }

      await bs.from("ingestion_runs").update({status:"consulting_mapping",current_stage:"consulting_mapping",updated_at:new Date().toISOString()}).eq("id",id);
      const {data:survivors}=await bs.from("extraction_candidates").select("*").eq("run_id",id).eq("candidate_status","normalized").order("created_at");
      const {data:jobs}=await bs.from("consulting_jobs").select("id,slug,name,description,expected_output,user_questions").eq("status","active");
      const mapStage=await stageStart(id,null,"consulting_mapping","consulting_mapper");
      try {
        const mapped=await callAgent("consulting_mapper",{
          task:"Map canonical candidate objects to existing consulting jobs. Do not invent knowledge. Return only meaningful links and explicit coverage gaps.",
          required_output:{
            links:[{candidate_id:"uuid",job_id:"uuid",knowledge_role:"string",relevance:"0..1",rationale:"string"}],
            gaps:[{job_id:"uuid",severity:"info|warning",description:"string"}]
          },
          knowledge:(survivors??[]).map((c:Record<string,unknown>)=>({id:c.id,name:c.provisional_name,type:c.object_type,summary:c.summary,scope:c.scope,conditions:c.conditions,limitations:c.limitations,topics:c.topics})),
          jobs:jobs??[],
        },16000);
        await bs.from("candidate_job_links").delete().eq("run_id",id);
        let linkCount=0;
        for(const raw of arr(mapped.data.links)){
          const l=obj(raw); if(!uuid(l.candidate_id)||!uuid(l.job_id)) continue;
          const {error}=await bs.from("candidate_job_links").upsert({
            run_id:id,candidate_id:l.candidate_id,job_id:l.job_id,knowledge_role:text(l.knowledge_role,120)||"supporting",
            relevance:num(l.relevance,0.5),rationale:text(l.rationale,3000)||"Relevância consultiva",validation_status:"proposed",
            created_by_stage_run_id:mapStage.id,
          },{onConflict:"candidate_id,job_id"});
          if(!error) linkCount++;
        }
        for(const raw of arr(mapped.data.gaps)){
          const g=obj(raw); if(!uuid(g.job_id)) continue;
          await bs.from("ingestion_qa_findings").insert({
            run_id:id,stage_run_id:mapStage.id,finding_type:"coverage_gap",
            severity:text(g.severity,20)==="warning"?"warning":"info",entity_type:"consulting_job",entity_id:g.job_id,
            description:text(g.description,4000)||"Lacuna de cobertura",status:"open",
          });
        }
        await stageDone(String(mapStage.id),`${linkCount} vínculos consultivos propostos`,{links:linkCount});
      } catch(e){ await stageFail(String(mapStage.id),e); throw e; }

      await bs.from("ingestion_runs").update({status:"qa",current_stage:"qa",updated_at:new Date().toISOString()}).eq("id",id);
      const qaStage=await stageStart(id,null,"qa","red_team");
      try {
        const [{data:normalizedCandidates},{data:rels},{data:links},{data:sections},{data:groundings}] = await Promise.all([
          bs.from("extraction_candidates").select("*").eq("run_id",id).eq("candidate_status","normalized"),
          bs.from("candidate_relationships").select("*").eq("run_id",id),
          bs.from("candidate_job_links").select("*").eq("run_id",id),
          bs.from("source_sections").select("id,title,section_type,processing_status,parent_section_id").eq("source_id",run.source_id),
          bs.from("candidate_groundings").select("candidate_id,fidelity_status").in("candidate_id",(survivors??[]).map((c:Record<string,unknown>)=>c.id as string)),
        ]);
        const norm=(normalizedCandidates??[]) as Record<string,unknown>[];
        const verifiedGroundingIds=new Set((groundings??[]).filter((g:Record<string,unknown>)=>g.fidelity_status==="verified").map((g:Record<string,unknown>)=>g.candidate_id));
        for(const c of norm){
          if(!verifiedGroundingIds.has(c.id)) await bs.from("ingestion_qa_findings").insert({
            run_id:id,stage_run_id:qaStage.id,finding_type:"missing_verified_grounding",severity:"critical",
            entity_type:"candidate",entity_id:c.id,description:"Objeto normalizado sem grounding verificado.",status:"open",
          });
        }
        const childParents=new Set((sections??[]).map((s:Record<string,unknown>)=>s.parent_section_id).filter(Boolean));
        for(const s of (sections??[]) as Record<string,unknown>[]){
          if(!childParents.has(s.id) && s.processing_status!=="processed") await bs.from("ingestion_qa_findings").insert({
            run_id:id,stage_run_id:qaStage.id,finding_type:"unprocessed_leaf_section",severity:"critical",
            entity_type:"source_section",entity_id:s.id,description:`Seção ainda não processada: ${String(s.title??s.id)}`,status:"open",
          });
        }
        const connected=new Set<string>();
        for(const r of (rels??[]) as Record<string,unknown>[]){ connected.add(String(r.from_candidate_id)); connected.add(String(r.to_candidate_id)); }
        for(const c of norm){
          if(norm.length>1 && !connected.has(String(c.id))) await bs.from("ingestion_qa_findings").insert({
            run_id:id,stage_run_id:qaStage.id,finding_type:"isolated_object",severity:"warning",
            entity_type:"candidate",entity_id:c.id,description:"Objeto normalizado sem relações propostas.",status:"open",
          });
        }
        const red=await callAgent("red_team",{
          task:"Red-team this ingestion. Find fidelity, granularity, relation, universality, contamination and decision-risk problems. Mandatory: identify bad decisions the base could induce.",
          required_output:{findings:[{finding_type:"string",severity:"info|warning|critical",entity_type:"candidate|relationship|job_link|run",entity_id:"uuid|null",description:"string",evidence:{note:"string"}}]},
          knowledge:norm.map((c)=>({id:c.id,name:c.provisional_name,type:c.object_type,summary:c.summary,scope:c.scope,conditions:c.conditions,limitations:c.limitations,epistemic_status:c.epistemic_status,portability:c.portability})),
          relationships:rels??[],job_links:links??[],
        },12000);
        let aiFindings=0;
        for(const raw of arr(red.data.findings)){
          const f=obj(raw); const severity=["info","warning","critical"].includes(text(f.severity,20))?text(f.severity,20):"warning";
          await bs.from("ingestion_qa_findings").insert({
            run_id:id,stage_run_id:qaStage.id,finding_type:text(f.finding_type,120)||"red_team",
            severity,entity_type:text(f.entity_type,80)||"run",entity_id:uuid(f.entity_id)?f.entity_id:null,
            description:text(f.description,4000)||"Finding do Red Team",evidence:obj(f.evidence),status:"open",
          }); aiFindings++;
        }
        const {count:critical}=await bs.from("ingestion_qa_findings").select("id",{count:"exact",head:true}).eq("run_id",id).eq("severity","critical").eq("status","open");
        if((critical??0)===0){
          await bs.from("candidate_relationships").update({validation_status:"verified"}).eq("run_id",id).eq("validation_status","proposed");
          await bs.from("candidate_job_links").update({validation_status:"verified"}).eq("run_id",id).eq("validation_status","proposed");
          await bs.from("ingestion_runs").update({status:"ready_to_publish",current_stage:"ready_to_publish",updated_at:new Date().toISOString()}).eq("id",id);
        }
        await stageDone(String(qaStage.id),`${critical??0} findings críticos abertos`,{ai_findings:aiFindings,critical:critical??0});
        return json(req,200,{ok:true,status:(critical??0)===0?"ready_to_publish":"qa",critical_findings:critical??0},requestId);
      } catch(e){ await stageFail(String(qaStage.id),e); throw e; }
    }

    if (action === "publish" && req.method === "POST") {
      const {data,error}=await admin.rpc("mind_business_publish_ingestion_run",{p_run_id:id});
      if(error) return json(req,422,{ok:false,error:error.message},requestId);
      return json(req,200,{ok:true,published:data},requestId);
    }

    return json(req,404,{ok:false,error:"not_found"},requestId);
  } catch(e) {
    console.error(JSON.stringify({request_id:requestId,error:e instanceof Error?e.message:String(e)}));
    return json(req,500,{ok:false,error:e instanceof Error?e.message:"internal_error",request_id:requestId},requestId);
  }
});