const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const html=fs.readFileSync(process.argv[2]||'index.html','utf8');
for(const m of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))if(m[1].trim())new vm.Script(m[1]);
function section(start,end){const a=html.indexOf(start),b=html.indexOf(end,a+start.length);assert(a>=0&&b>a);return html.slice(a,b);}
function harness(){
  const fields={},toasts=[];let writes=0,render=0,closed=0;
  const ctx={console,Number,Date,Array,CU:{perfil:'master'},DB:{materiais:[{id:'test',n:'Teste',disp:1,cont:1}]},_matEditId:null,
    document:{body:{style:{}},getElementById:id=>fields[id]||(fields[id]={value:'',style:{}}),querySelector:()=>fields.btn||(fields.btn={})},
    showToast:(...x)=>toasts.push(x),getMats:()=>ctx.DB.materiais,saveDB:()=>writes++,renderEstoqueGrid:()=>render++,fecharModalMov:()=>closed++,fecharModalMaterial:()=>closed++,escaparCidadeHTML:String};
  vm.createContext(ctx);return {ctx,fields,toasts,stats:()=>({writes,render,closed})};
}
(async()=>{
  const mov=section('async function salvarMovimentacao(){','// ═══ RELATÓRIOS');
  for(const mode of ['success','denied','race','insufficient']){
    const h=harness();Object.assign(h.fields,{'mov-material':{value:'test'},'mov-tipo':{value:'saida'},'mov-qtd':{value:mode==='insufficient'?'2':'1'}});
    h.ctx.sbSelect=async()=>[{id:'stock',quantidade_disponivel:1,quantidade_contratada:1}];
    h.ctx.sbFetch=async(filter,method,row)=>{assert(filter.includes('quantidade_disponivel=eq.1'));assert.equal(row.quantidade_disponivel,0);if(mode==='denied')throw Error('Sem permissão');return mode==='race'?[]:[{id:'stock'}];};
    vm.runInContext(mov,h.ctx);await h.ctx.salvarMovimentacao();
    assert.equal(h.ctx.DB.materiais[0].disp,mode==='success'?0:1,mode);assert.equal(h.stats().writes,mode==='success'?1:0);assert.equal(h.fields.btn.disabled,false);
  }
  for(const ok of [true,false]){
    const h=harness();for(const [id,value] of Object.entries({'mat-nome':'Teste novo','mat-unidade':'Un.','mat-cont':'1','mat-disp':'1','mat-min':'0','mat-preco':'0'}))h.fields[id]={value,style:{}};
    h.ctx.sbSaveMaterial=async()=>ok?'saved-uuid':false;
    vm.runInContext(section('async function salvarMaterial(){','async function abrirHistoricoMovimentacao()'),h.ctx);await h.ctx.salvarMaterial();
    assert.equal(h.ctx.DB.materiais.length,ok?2:1);assert.equal(h.stats().writes,ok?1:0);assert.equal(h.stats().closed,ok?1:0);
  }
  const h=harness();h.ctx.vEstoque=()=>{};
  vm.runInContext(section('function abrirMovimentacao(matId){','async function salvarMovimentacao(){'),h.ctx);
  h.ctx.abrirMovimentacao('test');assert(h.fields['mov-material'].innerHTML.includes('Teste (1 disponíveis)'));
  h.ctx.DB.materiais.push({id:'new',n:'Novo',disp:2});h.ctx.abrirMovimentacao('new');assert(h.fields['mov-material'].innerHTML.includes('Novo (2 disponíveis)'));
  const create=section('async function salvarChamadoInterno(){','// ═══ PORTAL PÚBLICO');
  const c=harness();Object.assign(c.ctx,{CU:{perfil:'master',nome:'Teste'},DB:{cidades:[{id:'city',nome:'Manhuaçu',consorcio_id:'cons'}],historico:{}},window:{},intProb:'Lâmpada apagada',gerarProto:()=> 'TEST-PROTO',tentarGeocodar:async()=>null,sbSaveHistorico:async()=>{},showView:()=>{}});
  for(const [id,value] of Object.entries({'int-cidade':'Manhuaçu','int-bairro':'TESTE','int-end':'TESTE - NÃO EXECUTAR','int-area':'Urbana','int-qtd':'1','int-obs':'teste','int-emp':''}))c.fields[id]={value};
  c.ctx.sbSaveChamado=async row=>{assert.equal(row.endereco,'TESTE - NÃO EXECUTAR');assert.equal(row.cidade_id,'city');return true;};
  vm.runInContext(create,c.ctx);await c.ctx.salvarChamadoInterno();assert(c.toasts.some(x=>x[0].includes('confirmado no banco')));
  console.log('PASS: syntax, creation, material success/denial, dynamic choices, stock success/denial/conflict/insufficient balance (9 scenarios).');
})().catch(e=>{console.error(e);process.exitCode=1;});

