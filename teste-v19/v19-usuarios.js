// V19 — Gestão de usuários vinculada a Supabase Auth + Edge Function.
// A tela antiga continua no HTML como legado, mas este módulo substitui seu fluxo visual.
// Nunca envia senhas, chave service_role ou operações diretas às tabelas.
(function () {
  "use strict";
  let usuarios = [];
  let catalogos = { consorcios: [], cidades: [], empresas: [] };
  let editando = null;
  let ocupado = false;
  const perfis = {
    master: "Admin Master", consorcio: "Gestor de Consórcio",
    prefeitura: "Prefeitura", empresa: "Empresa", garantia: "Garantia LED",
  };
  const admin = () => CU && ["master", "consorcio"].includes(CU.perfil);
  const esc = (x) => String(x == null ? "" : x).replace(/[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const rolesDisponiveis = () => CU?.perfil === "master"
    ? ["master", "consorcio", "prefeitura", "empresa", "garantia"]
    : ["prefeitura", "empresa", "garantia"];
  const validUuid = (x) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(x || "");
  const aviso = (msg, tipo) => {
    if (typeof showToast === "function") showToast(msg, tipo || "aviso");
  };
  async function api(payload, retry = false) {
    if (!SUPA_CONFIGURADO || !SB_SESSION?.access_token)
      throw new Error("Faça login novamente no projeto de homologação V19.");
    const response = await fetch(SUPA_URL + "/functions/v1/v19-usuarios", {
      method: "POST",
      headers: {
        "apikey": SUPA_KEY,
        "authorization": "Bearer " + SB_SESSION.access_token,
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    if (response.status === 401 && !retry && typeof sbRefreshSession === "function" &&
        await sbRefreshSession()) return api(payload, true);
    const result = await response.json().catch(() => ({}));
    if (!response.ok || result.ok !== true) {
      const mensagens = {
        SEM_PERMISSAO_DE_ADMINISTRACAO: "Seu perfil não pode gerenciar usuários.",
        USUARIO_FORA_DA_ADMINISTRACAO: "Este usuário pertence a outro escopo.",
        ESCOPO_NAO_AUTORIZADO: "Perfil ou consórcio não autorizado.",
        CONSORCIO_INATIVO_OU_INEXISTENTE: "Selecione um consórcio ativo.",
        CIDADE_NAO_AUTORIZADA: "Selecione um município ativo desse consórcio.",
        EMPRESA_NAO_AUTORIZADA: "Selecione uma empresa ativa desse consórcio.",
        AUTOALTERACAO_ADMIN_BLOQUEADA: "A alteração do seu próprio perfil administrativo está bloqueada.",
        REGISTRO_DUPLICADO: "Já existe um cadastro com esse e-mail.",
        CONVITE_NAO_ENVIADO: "O Supabase Auth não confirmou o envio do convite.",
        EMAIL_IMUTAVEL: "A mudança de e-mail deve ser feita por um fluxo administrativo separado.",
        STATUS_MASTER_RESTRITO: "Para proteger o administrador Master, esta ação está bloqueada.",
        PERFIL_SEM_CONTA_AUTH: "Este usuário ainda não possui conta Auth vinculada.",
        VINCULO_AUTH_NAO_CONFIRMADO_REQUER_RECONCILIACAO:
          "Convite iniciado, mas o vínculo não foi confirmado. Não repita o cadastro; solicite reconciliação administrativa.",
      };
      throw new Error(mensagens[result.codigo] || ("Operação não confirmada (" +
        esc(result.codigo || response.status) + ")."));
    }
    return result;
  }
  async function carregarCatalogos() {
    const [consorcios, cidades, empresas] = await Promise.all([
      sbSelect("consorcios", "select=id,nome,status&status=eq.ativo&order=nome.asc"),
      sbSelect("cidades", "select=id,nome,consorcio_id,status&status=eq.ativo&order=nome.asc"),
      sbSelect("empresas", "select=id,nome,consorcio_id,status&status=eq.ativo&order=nome.asc"),
    ]);
    if (![consorcios, cidades, empresas].every(Array.isArray))
      throw new Error("Não foi possível consultar os vínculos reais no Supabase.");
    catalogos = { consorcios, cidades, empresas };
  }
  async function carregarUsuarios() {
    const rows = await sbSelect("usuarios",
      "select=id,auth_user_id,consorcio_id,cidade_id,empresa_id,nome,email,telefone,cpf,cargo,perfil,status,org,created_at&order=nome.asc");
    if (!Array.isArray(rows)) throw new Error("Consulta de usuários não autorizada ou indisponível.");
    usuarios = rows;
    // Compatibilidade com outros painéis da V19, sem cache persistente.
    DB.usuarios = rows.map((u) => ({
      ...u, criado_em: u.created_at,
      av: (u.nome || "U").trim().split(/\s+/).slice(0, 2).map((x) => x[0] || "").join("").toUpperCase(),
      cor: "#1251A3",
    }));
  }
  function renderLista(b, t, a) {
    t.textContent = "Usuários e permissões · V19";
    a.innerHTML = '<button type="button" class="btn btn-save" id="v19-usuario-adicionar">+ Convidar usuário</button>';
    b.innerHTML = '<div class="tcard" style="padding:18px">' +
      '<div style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:16px">' +
      '<input id="v19-usr-busca" placeholder="Buscar nome ou e-mail" style="min-width:250px;flex:1;padding:10px;border:1px solid #cbd5e1;border-radius:8px">' +
      '<select id="v19-usr-perfil-filtro" style="padding:10px;border:1px solid #cbd5e1;border-radius:8px"><option value="">Todos os perfis</option>' +
      Object.entries(perfis).map(([v, n]) => '<option value="' + esc(v) + '">' + esc(n) + '</option>').join("") +
      '</select><span id="v19-usr-contador" style="font-size:12px"></span></div>' +
      '<div style="overflow-x:auto"><table style="width:100%;border-collapse:collapse">' +
      '<thead><tr><th>Usuário</th><th>Perfil</th><th>Organização</th><th>Situação</th><th>Ações</th></tr></thead>' +
      '<tbody id="v19-usr-linhas"></tbody></table></div>' +
      '<p style="font-size:12px;color:#64748b;margin-top:12px">O cadastro envia convite por e-mail; senhas não são cadastradas nesta tela. ' +
      'Excluir foi substituído por desativar, preservando os históricos.</p></div>';
    const podeAlterar = (u) => CU?.perfil === "master" ||
      (CU?.perfil === "consorcio" && u.consorcio_id === CU.consorcio_id &&
       ["prefeitura", "empresa", "garantia"].includes(u.perfil));
    const desenhar = () => {
      const busca = (document.getElementById("v19-usr-busca")?.value || "").trim().toLocaleLowerCase("pt-BR");
      const p = document.getElementById("v19-usr-perfil-filtro")?.value || "";
      const visiveis = usuarios.filter((u) => (!p || u.perfil === p) &&
        (!busca || (u.nome + " " + u.email).toLocaleLowerCase("pt-BR").includes(busca)));
      const tbody = document.getElementById("v19-usr-linhas");
      const total = document.getElementById("v19-usr-contador");
      if (total) total.textContent = visiveis.length + " usuário(s)";
      if (!tbody) return;
      tbody.innerHTML = visiveis.map((u) =>
        '<tr style="border-bottom:1px solid #e2e8f0">' +
          '<td style="padding:10px"><strong>' + esc(u.nome) + '</strong><div style="font-size:11px;color:#64748b">' +
            esc(u.email) + '</div></td>' +
          '<td style="padding:10px">' + esc(perfis[u.perfil] || u.perfil) + '</td>' +
          '<td style="padding:10px">' + esc(u.org || u.consorcio_id || "—") + '</td>' +
          '<td style="padding:10px">' + esc(u.status) + (u.auth_user_id ? "" : " · sem Auth") + '</td>' +
          '<td style="padding:10px;white-space:nowrap">' +
            (u.id === CU?.id ? '<span style="color:#64748b">Conta atual</span>' : !podeAlterar(u) ? '<span style="color:#64748b">Somente leitura</span>' :
              '<button type="button" class="btn btn-ghost" data-edit="' + esc(u.id) + '">Editar</button> ' +
              (u.perfil === "master" ? '<span style="color:#64748b">Protegido</span>' :
                '<button type="button" class="btn btn-ghost" data-status="' + esc(u.id) + '">' +
                (u.status === "ativo" ? "Desativar" : "Ativar") + '</button>')) +
          '</td></tr>').join("") ||
        '<tr><td colspan="5" style="padding:20px">Nenhum usuário encontrado.</td></tr>';
    };
    document.getElementById("v19-usuario-adicionar")?.addEventListener("click", () => abrirFormulario(null));
    document.getElementById("v19-usr-busca")?.addEventListener("input", desenhar);
    document.getElementById("v19-usr-perfil-filtro")?.addEventListener("change", desenhar);
    document.getElementById("v19-usr-linhas")?.addEventListener("click", (event) => {
      const botao = event.target.closest("button");
      if (!botao) return;
      if (botao.dataset.edit) abrirFormulario(botao.dataset.edit);
      if (botao.dataset.status) alterarStatus(botao.dataset.status);
    });
    desenhar();
  }
  async function atualizarVisao() {
    const b = document.getElementById("main-body");
    const t = document.getElementById("topbar-title");
    const a = document.getElementById("topbar-actions");
    if (!b || !t || !a || t.textContent !== "Usuários e permissões · V19") return;
    await carregarUsuarios();
    renderLista(b, t, a);
  }
  async function alterarStatus(id) {
    if (ocupado) return;
    const u = usuarios.find((row) => row.id === id);
    if (!u || u.id === CU?.id || u.perfil === "master") return;
    const proximo = u.status === "ativo" ? "inativo" : "ativo";
    if (!window.confirm((proximo === "inativo" ? "Desativar" : "Ativar") +
        ' o usuário "' + u.nome + '"? A alteração será gravada no Supabase.')) return;
    ocupado = true;
    try {
      const result = await api({ acao: "alterar_status", usuario_id: u.id, status: proximo });
      if (result.auditoria_confirmada !== true) aviso("Status salvo, mas a auditoria não foi confirmada.", "aviso");
      else aviso("Status confirmado no Supabase V19.", "ok");
      await atualizarVisao();
    } catch (e) { aviso("Falha: " + e.message, "erro"); }
    finally { ocupado = false; }
  }
  function selectOpcoes(arr, selecionado) {
    return '<option value="">Selecione</option>' +
      arr.map((x) => '<option value="' + esc(x.id) + '"' + (x.id === selecionado ? " selected" : "") +
        '>' + esc(x.nome) + "</option>").join("");
  }
  function abrirFormulario(id) {
    if (!admin() || ocupado) return;
    const original = id ? usuarios.find((u) => u.id === id) : null;
    if (id && !original) return;
    editando = original;
    const perfilAtual = original?.perfil || rolesDisponiveis()[0];
    const idModal = "v19-usr-modal";
    document.getElementById(idModal)?.remove();
    const overlay = document.createElement("div");
    overlay.id = idModal;
    overlay.style.cssText = "position:fixed;inset:0;z-index:100000;background:rgba(2,6,23,.65);display:flex;align-items:center;justify-content:center;padding:12px;";
    const consPadrao = original?.consorcio_id || (CU?.perfil === "consorcio" ? CU.consorcio_id : "");
    overlay.innerHTML = '<div role="dialog" aria-modal="true" aria-label="Cadastro de usuário" style="max-width:680px;width:100%;max-height:92vh;overflow:auto;background:#fff;border-radius:14px;padding:22px;color:#0f172a">' +
      '<h3 style="margin:0 0 6px">' + (original ? "Editar usuário" : "Convidar novo usuário") + '</h3>' +
      '<p style="color:#64748b;font-size:13px;margin:0 0 16px">' +
        (original ? "As alterações só serão exibidas como concluídas após confirmação do servidor." :
          "O usuário receberá um convite do Supabase Auth para definir a própria senha.") + '</p>' +
      '<form id="v19-usr-form" style="display:grid;grid-template-columns:1fr 1fr;gap:12px">' +
        campo("Nome", "nome", original?.nome, true) +
        campo("E-mail" + (original ? " (imutável)" : ""), "email", original?.email, true, !!original) +
        campo("Telefone", "telefone", original?.telefone) +
        campo("Cargo", "cargo", original?.cargo) +
        campo("CPF", "cpf", original?.cpf) +
        '<label style="font-size:12px;font-weight:600">Perfil<select id="v19-f-perfil" required style="display:block;width:100%;padding:10px;margin-top:4px;border:1px solid #cbd5e1;border-radius:6px">' +
        rolesDisponiveis().map((p) => '<option value="' + esc(p) + '"' +
          (p === perfilAtual ? " selected" : "") + '>' + esc(perfis[p]) + '</option>').join("") +
        '</select></label>' +
        '<label id="v19-f-wrap-cons" style="font-size:12px;font-weight:600">Consórcio<select id="v19-f-cons" style="display:block;width:100%;padding:10px;margin-top:4px;border:1px solid #cbd5e1;border-radius:6px" ' +
          (CU?.perfil === "consorcio" ? "disabled" : "") + ">" +
          selectOpcoes(catalogos.consorcios, consPadrao) + '</select></label>' +
        '<label id="v19-f-wrap-cidade" style="font-size:12px;font-weight:600">Município<select id="v19-f-cidade" style="display:block;width:100%;padding:10px;margin-top:4px;border:1px solid #cbd5e1;border-radius:6px"></select></label>' +
        '<label id="v19-f-wrap-empresa" style="font-size:12px;font-weight:600">Empresa<select id="v19-f-empresa" style="display:block;width:100%;padding:10px;margin-top:4px;border:1px solid #cbd5e1;border-radius:6px"></select></label>' +
        '<div style="grid-column:1/-1;display:flex;gap:8px;justify-content:flex-end;margin-top:10px">' +
          '<button type="button" id="v19-usr-cancelar" class="btn btn-ghost">Cancelar</button>' +
          '<button type="submit" id="v19-usr-confirmar" class="btn btn-save">' +
          (original ? "Salvar no Supabase" : "Enviar convite") + '</button></div>' +
      '</form></div>';
    document.body.appendChild(overlay);
    overlay.querySelector("#v19-usr-cancelar")?.addEventListener("click", () => overlay.remove());
    overlay.addEventListener("click", (e) => { if (e.target === overlay) overlay.remove(); });
    const perfilSelect = overlay.querySelector("#v19-f-perfil");
    const consSelect = overlay.querySelector("#v19-f-cons");
    const refazerVinculos = () => {
      const perf = perfilSelect.value;
      const cons = CU?.perfil === "consorcio" ? CU.consorcio_id : consSelect.value;
      overlay.querySelector("#v19-f-wrap-cons").style.display = perf === "master" ? "none" : "";
      overlay.querySelector("#v19-f-wrap-cidade").style.display = perf === "prefeitura" ? "" : "none";
      overlay.querySelector("#v19-f-wrap-empresa").style.display = perf === "empresa" ? "" : "none";
      const cityList = catalogos.cidades.filter((x) => x.consorcio_id === cons);
      const empList = catalogos.empresas.filter((x) => x.consorcio_id === cons);
      const cityCurrent = overlay.querySelector("#v19-f-cidade").value || original?.cidade_id;
      const empCurrent = overlay.querySelector("#v19-f-empresa").value || original?.empresa_id;
      overlay.querySelector("#v19-f-cidade").innerHTML = selectOpcoes(cityList, cityCurrent);
      overlay.querySelector("#v19-f-empresa").innerHTML = selectOpcoes(empList, empCurrent);
    };
    perfilSelect.addEventListener("change", refazerVinculos);
    consSelect.addEventListener("change", refazerVinculos);
    refazerVinculos();
    overlay.querySelector("#v19-usr-form").addEventListener("submit", async (event) => {
      event.preventDefault();
      if (ocupado) return;
      const value = (k) => overlay.querySelector("#v19-f-" + k)?.value?.trim() || "";
      const perfil = value("perfil");
      const cons = CU?.perfil === "consorcio" ? CU.consorcio_id : value("cons");
      const novo = {
        nome: value("nome"), email: value("email"), perfil,
        telefone: value("telefone"), cpf: value("cpf"), cargo: value("cargo"),
        consorcio_id: perfil === "master" ? null : cons || null,
        cidade_id: perfil === "prefeitura" ? value("cidade") || null : null,
        empresa_id: perfil === "empresa" ? value("empresa") || null : null,
      };
      if (!novo.nome || !novo.email || (perfil !== "master" && !validUuid(novo.consorcio_id))) {
        aviso("Preencha os campos obrigatórios e selecione o consórcio.", "erro"); return;
      }
      ocupado = true;
      const btn = overlay.querySelector("#v19-usr-confirmar");
      btn.disabled = true;
      btn.textContent = "Confirmando…";
      try {
        const result = await api(original
          ? { acao: "editar", usuario_id: original.id, usuario: novo }
          : { acao: "criar", usuario: novo });
        if (result.auditoria_confirmada !== true) {
          aviso("Cadastro persistido, mas auditoria não confirmada. Verifique antes de prosseguir.", "aviso");
        } else aviso(original ? "Alteração confirmada no Supabase." :
          "Usuário vinculado ao Auth; convite solicitado com sucesso.", "ok");
        overlay.remove();
        await atualizarVisao();
      } catch (e) {
        aviso("Cadastro não confirmado: " + e.message, "erro");
      } finally {
        ocupado = false;
        if (btn.isConnected) { btn.disabled = false; btn.textContent = "Confirmar"; }
      }
    });
  }
  function campo(label, id, valor, required = false, disabled = false) {
    return '<label style="font-size:12px;font-weight:600">' + esc(label) +
      '<input id="v19-f-' + esc(id) + '" type="' + (id === "email" ? "email" : "text") +
      '" value="' + esc(valor || "") + '" maxlength="' +
      (id === "email" ? 320 : id === "nome" ? 250 : 160) +
      '" style="display:block;width:100%;padding:10px;margin-top:4px;border:1px solid #cbd5e1;border-radius:6px"' +
      (required ? " required" : "") + (disabled ? " disabled" : "") + "></label>";
  }
  window.vUsuarios = async function (b, t, a) {
    if (!admin()) {
      t.textContent = "Usuários";
      a.innerHTML = "";
      b.innerHTML = '<div class="tcard" style="padding:20px">Acesso restrito a Master e Gestor de Consórcio.</div>';
      return;
    }
    t.textContent = "Usuários e permissões · V19";
    a.innerHTML = "";
    b.innerHTML = '<div class="tcard" style="padding:20px">Carregando usuários e vínculos reais do Supabase...</div>';
    try {
      await Promise.all([carregarUsuarios(), carregarCatalogos()]);
      if (t.textContent !== "Usuários e permissões · V19" || !b.isConnected) return;
      renderLista(b, t, a);
    } catch (e) {
      if (t.textContent !== "Usuários e permissões · V19" || !b.isConnected) return;
      b.innerHTML = '<div class="tcard" style="padding:20px;color:#b91c1c">' +
        esc(e.message) + ' <button class="btn btn-ghost" onclick="showView(\'usuarios\')">Tentar novamente</button></div>';
    }
  };
  // Usuário desativado nunca poderá entrar pela interface, mesmo com JWT ainda válido.
  const perfilOriginal = window.sbMeuPerfil;
  if (typeof perfilOriginal === "function") {
    window.sbMeuPerfil = async function () {
      const perfil = await perfilOriginal();
      return perfil && perfil.status === "ativo" ? perfil : null;
    };
  }
  // Remove a opção de menu indevida para Prefeitura. O bloqueio real permanece no servidor.
  const setupOriginal = window.setupUI;
  if (typeof setupOriginal === "function") {
    window.setupUI = function (u) {
      setupOriginal(u);
      const item = document.getElementById("sb-usuarios");
      if (item) item.style.display = ["master", "consorcio"].includes(u?.perfil) ? "flex" : "none";
    };
  }
  console.info("[V19] Gestão de usuários: módulo preparado; requer Edge Function homologada.");
})();
