/* Aponte Cidadão V19 — configuração real do portal e prazos por consórcio */
(function(){
'use strict';
const esc=x=>String(x??'').replace(/[&<>"']/g,k=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[k]));
const valid=x=>/^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(String(x||''));
const admin=()=>CU && ['master','consorcio'].includes(CU.perfil);
let consorcios=[], selectedCons='', rules=[], portalRow=null;

async function carregarConsorcios(){
  if(CU?.perfil==='master'){
    const list=await sbSelect('consorcios','select=id,nome&order=nome.asc');
    if(!Array.isArray(list))throw new Error('Consórcios indisponíveis no banco.');
    return list;
  }
  if(!valid(CU?.consorcio_id))throw new Error('Seu perfil não tem consórcio vinculado.');
  const one=await sbSelect('consorcios','select=id,nome&id=eq.'+encodeURIComponent(CU.consorcio_id));
  if(!Array.isArray(one)||one.length!==1)throw new Error('Consórcio não encontrado.');
  return one;
}
const escolha=(selected,action)=>'<label style="font-size:12px;font-weight:600">Consórcio: </label>'+
  '<select id="v19-config-cons" onchange="'+action+'(this.value)" style="max-width:320px">'+
  consorcios.map(c=>'<option value="'+esc(c.id)+'" '+(selected===c.id?'selected':'')+'>'+esc(c.nome)+'</option>').join('')+'</select>';

window.v19MudarConsPortal=async function(id){
  if(!valid(id)||!consorcios.some(c=>c.id===id))return;
  selectedCons=id;
  const b=document.getElementById('main-body'),t=document.getElementById('topbar-title'),a=document.getElementById('topbar-actions');
  await window.vConfigPortal(b,t,a,id);
};
window.v19MudarConsSLA=async function(id){
  if(!valid(id)||!consorcios.some(c=>c.id===id))return;
  selectedCons=id;
  await window.vSLA(document.getElementById('main-body'),
    document.getElementById('topbar-title'),document.getElementById('topbar-actions'),id);
};

window.vConfigPortal=async function(b,t,a,consId){
  t.textContent='Configurações do portal público';
  a.innerHTML='';b.innerHTML='<div class="card">Lendo configurações do Supabase…</div>';
  if(!admin()){
    b.innerHTML='<div class="card">Somente Master e Consórcio podem gerenciar o portal.</div>';return;
  }
  try{
    consorcios=await carregarConsorcios();
    const chosen=valid(consId)?consId:valid(selectedCons)?selectedCons:consorcios[0]?.id;
    if(!chosen)throw new Error('Nenhum consórcio disponível.');
    selectedCons=chosen;
    const rows=await sbSelect('portal_configuracoes',
      'select=*&consorcio_id=eq.'+encodeURIComponent(chosen)+'&limit=1');
    if(!Array.isArray(rows))throw new Error('A tabela portal_configuracoes não está disponível. Aplique o pacote V19 em homologação.');
    if(t.textContent!=='Configurações do portal público'||!b.isConnected)return;
    portalRow=rows[0]||{consorcio_id:chosen,portal_ativo:true,abertura_portal_ativo:true,
      consulta_protocolo_ativo:true,gps_obrigatorio:false,mostrar_empresa:false,
      notificacao_whatsapp:false,telefone_contato:'',whatsapp_contato:'',prazo_medio_texto:''};
    const check=(id,field,label)=>'<label style="display:flex;align-items:center;gap:9px;font-size:13px;padding:8px 0">'+
      '<input type="checkbox" id="'+id+'" '+(portalRow[field]?'checked':'')+'> '+esc(label)+'</label>';
    b.innerHTML='<div class="card" style="max-width:760px">'+
      '<div style="margin-bottom:18px">'+escolha(chosen,'v19MudarConsPortal')+'</div>'+
      '<h3 style="font-size:15px;margin-bottom:8px">Serviços do portal cidadão</h3>'+
      check('v19-portal-ativo','portal_ativo','Portal público ativo')+
      check('v19-portal-abertura','abertura_portal_ativo','Permitir abertura de chamados')+
      check('v19-portal-consulta','consulta_protocolo_ativo','Permitir consulta de protocolo')+
      check('v19-portal-gps','gps_obrigatorio','GPS obrigatório para abertura')+
      check('v19-portal-empresa','mostrar_empresa','Exibir a empresa responsável')+
      check('v19-portal-whatsapp','notificacao_whatsapp','Notificações por WhatsApp (integração pendente)')+
      '<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-top:14px">'+
        '<label>Telefone de contato<input id="v19-portal-telefone" style="width:100%" maxlength="40" value="'+esc(portalRow.telefone_contato||'')+'"></label>'+
        '<label>WhatsApp de contato<input id="v19-portal-numero" style="width:100%" maxlength="40" value="'+esc(portalRow.whatsapp_contato||'')+'"></label>'+
      '</div><label style="display:block;margin-top:14px">Prazo médio (texto público)<input id="v19-portal-prazo" '+
      'style="display:block;width:100%" maxlength="150" value="'+esc(portalRow.prazo_medio_texto||'')+'"></label>'+
      '<p style="font-size:11px;color:var(--gray-500);margin:14px 0">Salvar altera a configuração no banco. '+
      'O endereço público do portal deve ser publicado e testado separadamente. '+
      'Marcar notificações por WhatsApp não envia mensagens sem uma integração configurada.</p>'+
      '<button class="btn btn-save" id="v19-portal-salvar" onclick="v19SalvarPortal()">💾 Salvar configurações</button></div>';
  }catch(e){b.innerHTML='<div class="card" style="color:var(--red)">'+esc(e.message)+'</div>';}
};

window.v19SalvarPortal=async function(){
  if(!admin()||!valid(selectedCons))return;
  const btn=document.getElementById('v19-portal-salvar');
  if(btn?.disabled)return;
  const g=id=>!!document.getElementById(id)?.checked;
  const v=id=>document.getElementById(id)?.value?.trim()||null;
  const data={consorcio_id:selectedCons,portal_ativo:g('v19-portal-ativo'),
    abertura_portal_ativo:g('v19-portal-abertura'),
    consulta_protocolo_ativo:g('v19-portal-consulta'),gps_obrigatorio:g('v19-portal-gps'),
    mostrar_empresa:g('v19-portal-empresa'),notificacao_whatsapp:g('v19-portal-whatsapp'),
    telefone_contato:v('v19-portal-telefone'),whatsapp_contato:v('v19-portal-numero'),
    prazo_medio_texto:v('v19-portal-prazo'),updated_at:new Date().toISOString()};
  btn.disabled=true;btn.textContent='Salvando…';
  try{
    const path=portalRow&&portalRow.updated_at?
      'portal_configuracoes?consorcio_id=eq.'+encodeURIComponent(selectedCons)+'&select=consorcio_id':
      'portal_configuracoes?select=consorcio_id';
    const resp=await sbFetch(path,portalRow?.updated_at?'PATCH':'POST',data);
    if(!Array.isArray(resp)||resp.length!==1||resp[0].consorcio_id!==selectedCons)
      throw new Error('O Supabase não confirmou a gravação da configuração.');
    portalRow={...data};
    showToast('✅ Configurações confirmadas no banco.','ok');
  }catch(e){showToast(esc(e.message),'erro');}
  finally{btn.disabled=false;btn.textContent='💾 Salvar configurações';}
};

window.vSLA=async function(b,t,a,consId){
  t.textContent='Configuração de SLA';a.innerHTML='';
  b.innerHTML='<div class="card">Lendo prazos do Supabase…</div>';
  try{
    consorcios=await carregarConsorcios();
    selectedCons=valid(consId)?consId:(valid(selectedCons)?selectedCons:consorcios[0]?.id);
    if(!selectedCons)throw new Error('Nenhum consórcio disponível.');
    const rows=await sbSelect('sla_configuracoes',
      'select=*&consorcio_id=eq.'+encodeURIComponent(selectedCons)+'&order=tipo_problema.asc');
    if(!Array.isArray(rows))throw new Error('Configurações de SLA indisponíveis no banco.');
    if(t.textContent!=='Configuração de SLA'||!b.isConnected)return;
    rules=rows;
    const canEdit=admin();
    const row=(r,i)=>'<tr>'+
      '<td style="padding:8px"><input data-sla-campo="tipo" data-idx="'+i+'" value="'+esc(r.tipo_problema)+'" '+
        (canEdit?'':'disabled')+' style="min-width:160px"></td>'+
      ['urb_prazo','urb_alerta','rur_prazo','rur_alerta'].map(k=>
        '<td style="padding:8px"><input type="number" min="1" max="8760" data-sla-campo="'+k+
        '" data-idx="'+i+'" value="'+esc(r[k])+'" style="width:85px" '+(canEdit?'':'disabled')+'></td>').join('')+
      '</tr>';
    b.innerHTML='<div class="card">'+escolha(selectedCons,'v19MudarConsSLA')+
      '<p style="font-size:11px;color:var(--gray-500);margin:14px 0">Prazos e alertas expressos em horas. '+
      'A configuração é específica por consórcio e persiste no Supabase.</p>'+
      '<div style="overflow:auto"><table><thead><tr><th>Tipo de problema</th>'+
      '<th>Urbano (h)</th><th>Alerta urbano (h)</th><th>Rural (h)</th>'+
      '<th>Alerta rural (h)</th></tr></thead><tbody id="v19-sla-linhas">'+
      (rules.length?rules.map(row).join(''):'<tr><td colspan="5">Nenhuma regra cadastrada para este consórcio.</td></tr>')+
      '</tbody></table></div>'+
      (canEdit?'<div style="display:flex;gap:10px;margin-top:14px">'+
      '<button class="btn btn-ghost" onclick="v19NovoSLA()">+ Novo prazo</button>'+
      '<button class="btn btn-save" id="v19-sla-salvar" onclick="v19SalvarSLA()">💾 Salvar prazos</button></div>':'')+
      '</div>';
  }catch(e){b.innerHTML='<div class="card" style="color:var(--red)">'+esc(e.message)+'</div>';}
};

window.v19NovoSLA=function(){
  if(!admin())return;
  const idx=rules.length;
  const linha={id:null,tipo_problema:'Nova ocorrência',urb_prazo:48,urb_alerta:12,rur_prazo:72,rur_alerta:24};
  rules.push(linha);
  const tbody=document.getElementById('v19-sla-linhas');
  if(!tbody)return;
  if(tbody.textContent.includes('Nenhuma regra'))tbody.innerHTML='';
  const row='<tr><td><input data-sla-campo="tipo" data-idx="'+idx+'" value="Nova ocorrência"></td>'+
    ['urb_prazo','urb_alerta','rur_prazo','rur_alerta'].map((k,i)=>
      '<td><input type="number" min="1" max="8760" data-sla-campo="'+k+'" data-idx="'+idx+
      '" style="width:80px" value="'+[48,12,72,24][i]+'"></td>').join('')+'</tr>';
  tbody.insertAdjacentHTML('beforeend',row);
};

window.v19SalvarSLA=async function(){
  if(!admin()||!valid(selectedCons))return;
  const btn=document.getElementById('v19-sla-salvar');
  if(btn?.disabled)return;
  const values=rules.map((r,i)=>{
    const g=k=>document.querySelector('[data-idx="'+i+'"][data-sla-campo="'+k+'"]')?.value;
    const q={consorcio_id:selectedCons,tipo_problema:(g('tipo')||'').trim(),updated_at:new Date().toISOString()};
    ['urb_prazo','urb_alerta','rur_prazo','rur_alerta'].forEach(k=>q[k]=Number(g(k)));
    if(r.id)q.id=r.id;
    return q;
  });
  if(values.some(x=>!x.tipo_problema||Object.entries(x)
     .some(([k,v])=>k.includes('_prazo')||k.includes('_alerta')
        ? !Number.isInteger(v)||v<1||v>8760:false))){
    showToast('Informe tipos de ocorrência e prazos válidos em horas.','erro');return;
  }
  const names=values.map(x=>x.tipo_problema.toLowerCase());
  if(new Set(names).size!==names.length){showToast('Existem tipos de ocorrência duplicados.','erro');return;}
  btn.disabled=true;btn.textContent='Salvando…';
  let completed=0;
  try{
    for(let i=0;i<values.length;i++){
      const r=values[i];
      const updating=!!rules[i].id;
      const url=updating?
        'sla_configuracoes?id=eq.'+encodeURIComponent(r.id)+'&select=id':
        'sla_configuracoes?select=id';
      const resp=await sbFetch(url,updating?'PATCH':'POST',r);
      if(!Array.isArray(resp)||resp.length!==1)
        throw new Error('O banco não confirmou o prazo "'+r.tipo_problema+'".');
      rules[i].id=resp[0].id;completed++;
    }
    showToast('✅ '+completed+' regras de SLA confirmadas no banco.','ok');
  }catch(e){
    showToast(esc(e.message)+' '+completed+' linha(s) salva(s); atualize a tela para conferir.','erro');
  }finally{btn.disabled=false;btn.textContent='💾 Salvar prazos';}
};
console.info('[Aponte V19] Portal e SLA com persistência real disponíveis.');
})();