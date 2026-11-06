// V19 — gestão de usuários exclusivamente do lado do servidor.
// Fase de desenvolvimento. Não publicar sem testes negativos e auditoria transacional.
// JWT do usuário é validado por @supabase/server; nenhuma credencial privilegiada é exposta no cliente.
import { createSupabaseContext } from "npm:@supabase/server@1";

type Perfil = "master" | "consorcio" | "prefeitura" | "empresa" | "garantia";
type Usuario = {
  id: string; auth_user_id: string | null; nome: string; email: string; status: string;
  perfil: Perfil; consorcio_id: string | null; cidade_id: string | null;
  empresa_id: string | null; telefone: string | null; cpf: string | null;
  cargo: string | null;
};
type InputUsuario = {
  nome?: unknown; email?: unknown; perfil?: unknown; consorcio_id?: unknown;
  cidade_id?: unknown; empresa_id?: unknown; telefone?: unknown;
  cpf?: unknown; cargo?: unknown;
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PERFIS: Perfil[] = ["master", "consorcio", "prefeitura", "empresa", "garantia"];
const SUBORDINADOS: Perfil[] = ["prefeitura", "empresa", "garantia"];
const baseOrigins = ["https://easyobrasandroid-source.github.io", "http://localhost:3000", "http://localhost:5173"];
const origins = new Set(baseOrigins.concat(
  (Deno.env.get("V19_ALLOWED_ORIGINS") || "").split(",").map((s) => s.trim()).filter(Boolean),
));
const originPermitida = (origin: string | null) => !origin || origins.has(origin);
function cors(origin: string | null): HeadersInit {
  return {
    "Access-Control-Allow-Origin": origin && origins.has(origin) ? origin : baseOrigins[0],
    "Access-Control-Allow-Headers": "authorization,apikey,content-type,x-client-info",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Access-Control-Max-Age": "3600",
    Vary: "Origin",
  };
}
function json(status: number, body: Record<string, unknown>, origin: string | null): Response {
  return Response.json(body, { status, headers: cors(origin) });
}
function fail(status: number, codigo: string, origin: string | null): Response {
  return json(status, { ok: false, codigo }, origin);
}
function texto(valor: unknown, max: number, obrigatorio = false): string | null {
  if (valor == null || valor === "") {
    if (obrigatorio) throw new Error("CAMPO_OBRIGATORIO");
    return null;
  }
  if (typeof valor !== "string") throw new Error("CAMPO_INVALIDO");
  const normal = valor.trim();
  if (normal.length > max || (obrigatorio && !normal)) throw new Error("CAMPO_INVALIDO");
  return normal || null;
}
function uuid(valor: unknown): string | null {
  if (valor === null || valor === undefined || valor === "") return null;
  if (typeof valor !== "string" || !UUID.test(valor)) throw new Error("UUID_INVALIDO");
  return valor;
}
function perfil(valor: unknown): Perfil {
  if (typeof valor !== "string" || !PERFIS.includes(valor as Perfil)) throw new Error("PERFIL_INVALIDO");
  return valor as Perfil;
}
function podeGerenciar(ator: Usuario, alvo: Pick<Usuario, "perfil" | "consorcio_id">): boolean {
  if (ator.perfil === "master") return true;
  return ator.perfil === "consorcio" &&
    SUBORDINADOS.includes(alvo.perfil) &&
    ator.consorcio_id !== null &&
    ator.consorcio_id === alvo.consorcio_id;
}
function erroBanco(error: { code?: string; message?: string } | null): string {
  if (!error) return "FALHA_NO_BANCO";
  if (error.code === "23505") return "REGISTRO_DUPLICADO";
  if (error.code === "23503") return "VINCULO_INEXISTENTE";
  if (error.code === "23514") return "ESCOPO_INVALIDO";
  return "FALHA_NO_BANCO";
}
Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");
  if (!originPermitida(origin)) return fail(403, "ORIGEM_NAO_PERMITIDA", origin);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });
  if (req.method !== "POST") return fail(405, "METODO_INVALIDO", origin);

  // Verifica JWT real, não aceita perfil nem identidade declarados no corpo.
  const { data: ctx, error: authError } = await createSupabaseContext(req, { auth: "user" });
  if (authError || !ctx?.userClaims?.id) return fail(401, "NAO_AUTENTICADO", origin);
  const db = ctx.supabaseAdmin;
  const { data: ator, error: erroAtor } = await ctx.supabase
    .from("usuarios")
    .select("id,auth_user_id,nome,email,status,perfil,consorcio_id,cidade_id,empresa_id")
    .eq("auth_user_id", ctx.userClaims.id)
    .eq("status", "ativo")
    .maybeSingle();
  if (erroAtor || !ator || !["master", "consorcio"].includes(ator.perfil)) {
    return fail(403, "SEM_PERMISSAO_DE_ADMINISTRACAO", origin);
  }
  const admin = ator as Usuario;
  let body: Record<string, unknown>;
  try {
    const raw = await req.text();
    if (raw.length > 12000) return fail(413, "REQUISICAO_MUITO_GRANDE", origin);
    body = JSON.parse(raw);
    if (!body || Array.isArray(body) || typeof body !== "object") {
      return fail(400, "REQUISICAO_INVALIDA", origin);
    }
  } catch {
    return fail(400, "JSON_INVALIDO", origin);
  }
  const acao = body.acao;
  if (!["criar", "editar", "alterar_status"].includes(String(acao))) {
    return fail(400, "ACAO_INVALIDA", origin);
  }

  // Os detalhes administrativos são construídos no servidor, sem senhas ou tokens.
  const registrar = async (alvoId: string, tipo: string, consorcioId: string | null, extra: string) => {
    return await db.from("auditoria").insert({
      consorcio_id: consorcioId,
      usuario_responsavel: admin.nome,
      acao: tipo,
      detalhes: "executor_id=" + admin.id + "; usuario_id=" + alvoId + "; " + extra,
    });
  };

  // Resolva sempre os vínculos contra as tabelas REAIS e seu consórcio.
  async function montar(input: InputUsuario) {
    const nome = texto(input.nome, 250, true)!;
    const email = texto(input.email, 320, true)?.toLowerCase() || "";
    if (!EMAIL.test(email)) throw new Error("EMAIL_INVALIDO");
    const perf = perfil(input.perfil);
    let cons = uuid(input.consorcio_id);
    let cidade = uuid(input.cidade_id);
    let empresa = uuid(input.empresa_id);
    let org: string;
    if (perf === "master") {
      if (cons || cidade || empresa) throw new Error("MASTER_SEM_VINCULOS");
      org = "Todos os consórcios";
    } else {
      if (!cons) throw new Error("CONSORCIO_OBRIGATORIO");
      const { data: c, error } = await db.from("consorcios")
        .select("id,nome").eq("id", cons).eq("status", "ativo").maybeSingle();
      if (error || !c) throw new Error("CONSORCIO_INATIVO_OU_INEXISTENTE");
      org = c.nome;
    }
    if (perf === "prefeitura") {
      if (!cidade || empresa) throw new Error("VINCULO_PREFEITURA_INVALIDO");
      const { data: ci, error } = await db.from("cidades")
        .select("id,nome").eq("id", cidade).eq("consorcio_id", cons!).eq("status", "ativo").maybeSingle();
      if (error || !ci) throw new Error("CIDADE_NAO_AUTORIZADA");
      org = ci.nome;
    } else {
      if (cidade) throw new Error("CIDADE_INDEVIDA_PARA_PERFIL");
      cidade = null;
    }
    if (perf === "empresa") {
      if (!empresa) throw new Error("EMPRESA_OBRIGATORIA");
      const { data: e, error } = await db.from("empresas")
        .select("id,nome").eq("id", empresa).eq("consorcio_id", cons!).eq("status", "ativo").maybeSingle();
      if (error || !e) throw new Error("EMPRESA_NAO_AUTORIZADA");
      org = e.nome;
    } else {
      if (empresa) throw new Error("EMPRESA_INDEVIDA_PARA_PERFIL");
      empresa = null;
    }
    const novo = {
      nome, email, perfil: perf, consorcio_id: cons, cidade_id: cidade,
      empresa_id: empresa,
      telefone: texto(input.telefone, 50),
      cpf: texto(input.cpf, 25),
      cargo: texto(input.cargo, 160),
      vinculo_tipo: perf,
      vinculo_id: perf === "empresa" ? empresa : perf === "prefeitura" ? cidade : cons,
      org,
    };
    if (!podeGerenciar(admin, novo)) throw new Error("ESCOPO_NAO_AUTORIZADO");
    return novo;
  }

  try {
    if (acao === "criar") {
      const dados = await montar((body.usuario || {}) as InputUsuario);
      // Pendente e inativo antes de enviar convite: sem perfil ativo órfão.
      const { data: pendente, error: inserirErro } = await db.from("usuarios")
        .insert({ ...dados, auth_user_id: null, status: "inativo" })
        .select("id").single();
      if (inserirErro || !pendente) return fail(409, erroBanco(inserirErro), origin);

      const { data: convite, error: conviteErro } = await db.auth.admin.inviteUserByEmail(dados.email);
      if (conviteErro || !convite?.user?.id) {
        const cleanup = await db.from("usuarios").delete()
          .eq("id", pendente.id).is("auth_user_id", null);
        if (cleanup.error) return fail(500, "CONVITE_FALHOU_E_CADASTRO_PENDENTE", origin);
        return fail(422, "CONVITE_NAO_ENVIADO", origin);
      }

      const { data: vinculado, error: vinculoErro } = await db.from("usuarios")
        .update({ auth_user_id: convite.user.id, status: "ativo", updated_at: new Date().toISOString() })
        .eq("id", pendente.id).is("auth_user_id", null).eq("status", "inativo")
        .select("id").single();
      if (vinculoErro || !vinculado) {
        // Nunca afirmar sucesso quando Auth e o perfil não estiverem vinculados.
        // Mantém cadastro inativo para recuperação supervisionada.
        await db.auth.admin.deleteUser(convite.user.id).catch(() => null);
        return fail(500, "VINCULO_AUTH_NAO_CONFIRMADO_REQUER_RECONCILIACAO", origin);
      }
      const audit = await registrar(pendente.id, "V19_USUARIO_CRIADO", dados.consorcio_id, "perfil=" + dados.perfil);
      return json(201, {
        ok: true, usuario_id: pendente.id, convite_enviado: true,
        auditoria_confirmada: !audit.error,
        ...(audit.error ? { aviso: "AUDITORIA_NAO_CONFIRMADA" } : {}),
      }, origin);
    }

    const alvoId = uuid(body.usuario_id);
    if (!alvoId) return fail(400, "USUARIO_ID_OBRIGATORIO", origin);
    const { data: alvo, error: erroAlvo } = await db.from("usuarios")
      .select("id,auth_user_id,nome,email,status,perfil,consorcio_id,cidade_id,empresa_id,telefone,cpf,cargo")
      .eq("id", alvoId).maybeSingle();
    if (erroAlvo || !alvo) return fail(404, "USUARIO_NAO_ENCONTRADO", origin);
    const anterior = alvo as Usuario;
    if (!podeGerenciar(admin, anterior)) return fail(403, "USUARIO_FORA_DA_ADMINISTRACAO", origin);
    if (alvoId === admin.id) return fail(403, "AUTOALTERACAO_ADMIN_BLOQUEADA", origin);

    if (acao === "editar") {
      const novo = await montar((body.usuario || {}) as InputUsuario);
      // E-mail não pode ser modificado por este fluxo: exige sincronismo próprio com Auth.
      if (novo.email !== anterior.email.toLowerCase()) return fail(422, "EMAIL_IMUTAVEL", origin);
      if (anterior.perfil === "master" && novo.perfil !== "master") {
        return fail(403, "REBAIXAMENTO_MASTER_BLOQUEADO", origin);
      }
      // Nunca permitir troca silenciosa de consórcio por um gestor.
      const { data: atualizado, error } = await db.from("usuarios").update({
        ...novo, updated_at: new Date().toISOString(),
      }).eq("id", alvoId).select("id").single();
      if (error || !atualizado) return fail(422, erroBanco(error), origin);
      const audit = await registrar(alvoId, "V19_USUARIO_EDITADO", novo.consorcio_id,
        "perfil=" + anterior.perfil + "->" + novo.perfil);
      return json(200, {
        ok: true, usuario_id: alvoId, auditoria_confirmada: !audit.error,
        ...(audit.error ? { aviso: "AUDITORIA_NAO_CONFIRMADA" } : {}),
      }, origin);
    }

    if (anterior.perfil === "master") return fail(403, "STATUS_MASTER_RESTRITO", origin);
    const estado = body.status;
    if (estado !== "ativo" && estado !== "inativo") return fail(400, "STATUS_INVALIDO", origin);
    if (anterior.status === estado) return fail(409, "STATUS_JA_DEFINIDO", origin);
    if (estado === "ativo" && !anterior.auth_user_id) {
      return fail(422, "PERFIL_SEM_CONTA_AUTH", origin);
    }
    const { data: atualizado, error } = await db.from("usuarios").update({
      status: estado, updated_at: new Date().toISOString(),
    }).eq("id", alvoId).eq("status", anterior.status).select("id").maybeSingle();
    if (error || !atualizado) return fail(409, "STATUS_NAO_CONFIRMADO", origin);
    const audit = await registrar(alvoId, "V19_USUARIO_STATUS", anterior.consorcio_id,
      "status=" + anterior.status + "->" + estado);
    return json(200, {
      ok: true, usuario_id: alvoId, status: estado, auditoria_confirmada: !audit.error,
      ...(audit.error ? { aviso: "AUDITORIA_NAO_CONFIRMADA" } : {}),
    }, origin);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "DADOS_INVALIDOS";
    const previstos = new Set([
      "CAMPO_OBRIGATORIO", "CAMPO_INVALIDO", "UUID_INVALIDO", "PERFIL_INVALIDO",
      "EMAIL_INVALIDO", "MASTER_SEM_VINCULOS", "CONSORCIO_OBRIGATORIO",
      "CONSORCIO_INATIVO_OU_INEXISTENTE", "VINCULO_PREFEITURA_INVALIDO",
      "CIDADE_NAO_AUTORIZADA", "CIDADE_INDEVIDA_PARA_PERFIL", "EMPRESA_OBRIGATORIA",
      "EMPRESA_NAO_AUTORIZADA", "EMPRESA_INDEVIDA_PARA_PERFIL", "ESCOPO_NAO_AUTORIZADO",
    ]);
    return fail(previstos.has(msg) ? 422 : 500, previstos.has(msg) ? msg : "ERRO_INTERNO", origin);
  }
});
