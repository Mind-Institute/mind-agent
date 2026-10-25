import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";
import { PDFDocument } from "npm:pdf-lib@1.17.1";
import { getDocumentProxy, extractText } from "npm:unpdf@1.7.0";

const VERSION = "1.0.0";
const BUCKET = "business-consulting-sources";

function readKey(name: "SUPABASE_PUBLISHABLE_KEYS" | "SUPABASE_SECRET_KEYS", fallback: string) {
  const raw = Deno.env.get(name);
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      if (typeof parsed.default === "string") return parsed.default;
      const first = Object.values(parsed).find((v) => typeof v === "string");
      if (typeof first === "string") return first;
    } catch {}
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
function obj(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
}
function arr(v: unknown): unknown[] { return Array.isArray(v) ? v : []; }
function text(v: unknown, max=20000) { return typeof v === "string" ? v.trim().slice(0,max) : ""; }
function num(v: unknown, fallback: number|null=null) {
  const n = typeof v === "number" ? v : Number(v);
  return Number.isFinite(n) ? n : fallback;
}
function uuid(v: unknown): v is string {
  return typeof v === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);
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
    return json(req,200,{ok:true,service:"mindagent-business-source",version:VERSION},requestId);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const pub = readKey("SUPABASE_PUBLISHABLE_KEYS","SUPABASE_ANON_KEY");
  const secret = readKey("SUPABASE_SECRET_KEYS","SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !pub || !secret) return json(req,503,{ok:false,error:"service_not_configured"},requestId);

  const bearer = (req.headers.get("Authorization") ?? "").match(/^Bearer\s+(.+)$/i)?.[1];
  if (!bearer) return json(req,401,{ok:false,error:"missing_session"},requestId);
  const publicClient = createClient(supabaseUrl,pub,{auth:{persistSession:false,autoRefreshToken:false}});
  const admin = createClient(supabaseUrl,secret,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:userData,error:userError}=await publicClient.auth.getUser(bearer);
  if(userError||!userData.user) return json(req,401,{ok:false,error:"invalid_session"},requestId);
  const {data:access}=await admin.from("mind_admin_users").select("active,role").eq("user_id",userData.user.id).maybeSingle();
  if(!access?.active) return json(req,403,{ok:false,error:"forbidden"},requestId);

  const bs=admin.schema("business_strategy");
  const openAiKey=Deno.env.get("OPENAI_API_KEY") ?? "";

  async function sourceSignedUrl(path:string) {
    const {data,error}=await admin.storage.from(BUCKET).createSignedUrl(path,3600);
    if(error||!data?.signedUrl) throw new Error("signed_url_failed");
    return data.signedUrl;
  }
  async function modelConfig() {
    const {data,error}=await bs.from("ingestion_agent_configs").select("*").eq("agent_key","source_extractor").eq("active",true).single();
    if(error||!data) throw new Error("source_extractor_config_missing");
    return data as Record<string,unknown>;
  }
  async function mapPdf(fileUrl:string) {
    if(!openAiKey) throw new Error("openai_not_configured");
    const cfg=await modelConfig();
    const r=await fetch("https://api.openai.com/v1/responses",{
      method:"POST",
      headers:{Authorization:`Bearer ${openAiKey}`,"Content-Type":"application/json"},
      body:JSON.stringify({
        model:String(cfg.model),
        instructions:String(cfg.instructions),
        input:[{role:"user",content:[
          {type:"input_file",file_url:fileUrl},
          {type:"input_text",text:JSON.stringify({
            task:"Mapeie a estrutura editorial completa deste livro antes de extrair conhecimento. Identifique unidades de leitura substantivas: front matter relevante, capítulos, subcapítulos relevantes, appendices, worksheets e afterword. Não extraia knowledge objects.",
            required_output:{sections:[{section_type:"front_matter|chapter|subchapter|appendix|worksheet|afterword|other",section_number:"string|null",title:"string",section_order:"integer",page_start:"integer|null",page_end:"integer|null"}]},
            rules:["Cobrir o PDF inteiro.","Usar coordenadas de página do PDF original.","Evitar headings decorativos.","Cada página substantiva deve pertencer a uma unidade de leitura."]
          })}
        ]}],
        reasoning:{effort:String(cfg.reasoning_effort??"high")},
        text:{format:{type:"json_object"}},
        max_output_tokens:14000,
        store:false
      })
    });
    if(!r.ok) throw new Error("openai_"+r.status+":"+(await r.text()).slice(0,500));
    const payload=await r.json() as Record<string,unknown>;
    return JSON.parse(extractOutput(payload)) as Record<string,unknown>;
  }

  const adminIndex=parts.lastIndexOf("admin");
  const resource=adminIndex>=0?parts[adminIndex+1]:undefined;
  const id=adminIndex>=0?parts[adminIndex+2]:undefined;
  const action=adminIndex>=0?parts[adminIndex+3]:undefined;

  try {
    if(resource==="upload" && req.method==="POST"){
      const form=await req.formData();
      const file=form.get("file");
      if(!(file instanceof File)) return json(req,422,{ok:false,error:"pdf_required"},requestId);
      if(file.type!=="application/pdf") return json(req,422,{ok:false,error:"pdf_only"},requestId);
      if(file.size<=0 || file.size>100*1024*1024) return json(req,422,{ok:false,error:"pdf_size_invalid"},requestId);

      const sourceId=crypto.randomUUID();
      const safe=(file.name||"source.pdf").normalize("NFD").replace(/[\u0300-\u036f]/g,"")
        .replace(/[^A-Za-z0-9._-]+/g,"_").slice(-180)||"source.pdf";
      const originalPath=`${sourceId}/original/${safe}`;
      const title=text(form.get("title"),400)||safe.replace(/\.pdf$/i,"").replace(/[_-]+/g," ");
      const authors=text(form.get("authors"),1200).split(/[;,\n]/).map((x)=>x.trim()).filter(Boolean);
      const yearRaw=text(form.get("publication_year"),10);
      const publicationYear=/^\d{4}$/.test(yearRaw)?Number(yearRaw):null;
      const isbn=text(form.get("isbn"),80)||null;

      const {error:uploadError}=await admin.storage.from(BUCKET).upload(originalPath,file,{contentType:"application/pdf",upsert:false,cacheControl:"3600"});
      if(uploadError) return json(req,500,{ok:false,error:"storage_upload_failed",detail:uploadError.message},requestId);

      const {data:source,error:sourceError}=await bs.from("sources").insert({
        id:sourceId,title,authors,source_type:"book",publication_year:publicationYear,isbn,
        access_scope:"mind_only",rights_status:"internal_source",ingestion_policy:"business_ingestion_v1",
        source_file_ref:`storage://${BUCKET}/${originalPath}`,
        metadata:{original_filename:file.name,storage_bucket:BUCKET,storage_path:originalPath,file_size:file.size,mime_type:file.type,uploaded_by:userData.user.id},
        validation_status:"pending"
      }).select("*").single();
      if(sourceError||!source){
        await admin.storage.from(BUCKET).remove([originalPath]);
        throw sourceError??new Error("source_create_failed");
      }

      const {data:run,error:runError}=await bs.from("ingestion_runs").insert({
        source_id:sourceId,status:"created",current_stage:"uploaded",requested_by:userData.user.id,
        started_at:new Date().toISOString(),metadata:{source_title:title,storage_path:originalPath,original_filename:file.name}
      }).select("*").single();
      if(runError) throw runError;
      return json(req,201,{ok:true,source,run},requestId);
    }

    if(resource==="runs" && uuid(id) && action==="map" && req.method==="POST"){
      const {data:run,error:runError}=await bs.from("ingestion_runs").select("*").eq("id",id).single();
      if(runError||!run) return json(req,404,{ok:false,error:"run_not_found"},requestId);
      const {data:source,error:sourceError}=await bs.from("sources").select("*").eq("id",run.source_id).single();
      if(sourceError||!source) return json(req,404,{ok:false,error:"source_not_found"},requestId);
      const md=obj(source.metadata);
      const storagePath=text(md.storage_path,1000);
      if(!storagePath) return json(req,409,{ok:false,error:"source_file_not_in_storage"},requestId);

      const cfg=await modelConfig();
      const {data:stage,error:stageError}=await bs.from("ingestion_stage_runs").insert({
        run_id:id,source_section_id:null,stage:"mapping",agent_key:"source_extractor",status:"running",
        model:cfg.model,prompt_version:cfg.prompt_version,started_at:new Date().toISOString()
      }).select("*").single();
      if(stageError) throw stageError;

      try{
        await bs.from("ingestion_runs").update({status:"mapping",current_stage:"mapping",updated_at:new Date().toISOString()}).eq("id",id);
        const mapped=await mapPdf(await sourceSignedUrl(storagePath));
        await bs.from("source_sections").delete().eq("source_id",run.source_id);
        const rows:Record<string,unknown>[]=[];
        for(const raw of arr(mapped.sections)){
          const s=obj(raw); const title=text(s.title,500); if(!title) continue;
          const {data:row,error}=await bs.from("source_sections").insert({
            source_id:run.source_id,parent_section_id:null,section_type:text(s.section_type,80)||"other",
            section_number:text(s.section_number,80)||null,title,section_order:num(s.section_order,rows.length+1),
            page_start:num(s.page_start),page_end:num(s.page_end),processing_status:"pending"
          }).select("*").single();
          if(error) throw error;
          rows.push(row);
        }
        await bs.from("ingestion_stage_runs").update({status:"completed",output_summary:`${rows.length} seções mapeadas`,metrics:{sections:rows.length},completed_at:new Date().toISOString()}).eq("id",stage.id);
        await bs.from("ingestion_runs").update({status:"created",current_stage:"mapped",metrics:{mapped_sections:rows.length},updated_at:new Date().toISOString()}).eq("id",id);
        return json(req,200,{ok:true,sections:rows},requestId);
      }catch(e){
        await bs.from("ingestion_stage_runs").update({status:"failed",error:e instanceof Error?e.message:String(e),completed_at:new Date().toISOString()}).eq("id",stage.id);
        await bs.from("ingestion_runs").update({status:"failed",error:e instanceof Error?e.message:String(e),updated_at:new Date().toISOString()}).eq("id",id);
        throw e;
      }
    }

    if(resource==="runs" && uuid(id) && action==="chunk" && req.method==="POST"){
      const {data:run,error:runError}=await bs.from("ingestion_runs").select("*").eq("id",id).single();
      if(runError||!run) return json(req,404,{ok:false,error:"run_not_found"},requestId);
      const {data:source}=await bs.from("sources").select("*").eq("id",run.source_id).single();
      const md=obj(source?.metadata);
      const storagePath=text(md.storage_path,1000);
      if(!storagePath) return json(req,409,{ok:false,error:"source_file_not_in_storage"},requestId);

      await bs.from("ingestion_runs").update({status:"mapping",current_stage:"chunking",updated_at:new Date().toISOString()}).eq("id",id);
      const {data:download,error:downloadError}=await admin.storage.from(BUCKET).download(storagePath);
      if(downloadError||!download) throw downloadError??new Error("source_download_failed");
      const bytes=new Uint8Array(await download.arrayBuffer());
      const src=await PDFDocument.load(bytes,{ignoreEncryption:true});
      const total=src.getPageCount();
      const {data:sections,error:sectionsError}=await bs.from("source_sections").select("*").eq("source_id",run.source_id).order("section_order");
      if(sectionsError) throw sectionsError;

      let made=0, skipped=0;
      for(const s of sections??[]){
        const start=Math.max(1,Number(s.page_start??1));
        const end=Math.min(total,Number(s.page_end??s.page_start??total));
        if(!Number.isFinite(start)||!Number.isFinite(end)||end<start){ skipped++; continue; }
        const out=await PDFDocument.create();
        const indexes=Array.from({length:end-start+1},(_,i)=>start-1+i);
        const pages=await out.copyPages(src,indexes);
        for(const p of pages) out.addPage(p);
        const outBytes=await out.save();
        const base=`${run.source_id}/sections/${s.id}`;
        const pdfPath=`${base}/section.pdf`;
        const jsonPath=`${base}/section.json`;
        let extractedText="";
        let textExtractionError:string|null=null;
        try {
          const proxy=await getDocumentProxy(outBytes);
          const extracted=await extractText(proxy,{mergePages:true});
          extractedText=typeof extracted.text==="string" ? extracted.text : Array.isArray(extracted.text) ? extracted.text.join("\n\n") : "";
        } catch(e) {
          textExtractionError=e instanceof Error?e.message:String(e);
        }
        const meta={
          source_id:run.source_id,section_id:s.id,title:s.title,section_number:s.section_number,
          source_page_start:start,source_page_end:end,original_source_file_ref:source.source_file_ref,
          derived_from:storagePath,generated_at:new Date().toISOString(),authority:"derived",
          text_extracted:Boolean(extractedText),text_extraction_error:textExtractionError
        };
        const {error:pdfError}=await admin.storage.from(BUCKET).upload(pdfPath,new Blob([outBytes],{type:"application/pdf"}),{contentType:"application/pdf",upsert:true});
        if(pdfError) throw pdfError;
        if(extractedText){
          const txtPath=`${base}/section.txt`;
          const {error:txtError}=await admin.storage.from(BUCKET).upload(txtPath,new Blob([extractedText],{type:"text/plain;charset=utf-8"}),{contentType:"text/plain;charset=utf-8",upsert:true});
          if(txtError) throw txtError;
        }
        const {error:jsonError}=await admin.storage.from(BUCKET).upload(jsonPath,new Blob([JSON.stringify(meta,null,2)],{type:"application/json"}),{contentType:"application/json",upsert:true});
        if(jsonError) throw jsonError;
        made++;
      }
      await bs.from("ingestion_runs").update({
        status:"created",current_stage:"ready_for_section_processing",
        metrics:{...(obj(run.metrics)),chunked_sections:made,skipped_sections:skipped},
        updated_at:new Date().toISOString()
      }).eq("id",id);
      return json(req,200,{ok:true,chunked:made,skipped,total_pages:total},requestId);
    }

    if(resource==="sources" && uuid(id) && action==="file" && req.method==="GET"){
      const {data:source,error}=await bs.from("sources").select("*").eq("id",id).single();
      if(error||!source) return json(req,404,{ok:false,error:"source_not_found"},requestId);
      const p=text(obj(source.metadata).storage_path,1000);
      if(!p) return json(req,409,{ok:false,error:"source_file_not_in_storage"},requestId);
      return json(req,200,{ok:true,url:await sourceSignedUrl(p),expires_in:3600},requestId);
    }

    if(resource==="sections" && uuid(id) && action==="file" && req.method==="GET"){
      const {data:s,error}=await bs.from("source_sections").select("id,source_id").eq("id",id).single();
      if(error||!s) return json(req,404,{ok:false,error:"section_not_found"},requestId);
      const p=`${s.source_id}/sections/${s.id}/section.pdf`;
      return json(req,200,{ok:true,url:await sourceSignedUrl(p),expires_in:3600},requestId);
    }

    return json(req,404,{ok:false,error:"not_found"},requestId);
  } catch(e) {
    console.error(JSON.stringify({request_id:requestId,error:e instanceof Error?e.message:String(e)}));
    return json(req,500,{ok:false,error:e instanceof Error?e.message:"internal_error",request_id:requestId},requestId);
  }
});