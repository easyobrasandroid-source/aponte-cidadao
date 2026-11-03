/* Aponte Cidadão V19 — verificação estática sem acesso ao banco
   Uso: node scripts/verificar-v19.mjs
   NÃO equivale a teste de segurança/RLS ou homologação de frontend. */
import {readFileSync, existsSync} from 'node:fs';
import {strict as assert} from 'node:assert';
import {execFileSync} from 'node:child_process';
const read = path=>readFileSync(path,'utf8');
const html=read('teste-v19/index.html');
const v18=read('teste-v18/index.html');
assert(html.includes('function vDashboard('),'V19 perdeu o dashboard');
assert(html.includes('function vMapa('),'V19 perdeu o mapa');
assert(html.includes('function vChamados('),'V19 perdeu a tela de chamados');
const scripts=['v19.js','v19-fotos.js','v19-relatorios.js','v19-config.js'];
const refs=[...html.matchAll(/<script\b[^>]*src=["']\.\/([^"']+)["'][^>]*><\/script>/g)].map(x=>x[1]);
for(const script of scripts){
  assert(refs.includes(script),'Script não referenciado: '+script);
  assert(existsSync('teste-v19/'+script),'Arquivo não encontrado: '+script);
  execFileSync(process.execPath,['--check','teste-v19/'+script],{stdio:'inherit'});
}
for(const match of html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi))
  if(match[1].trim()) new Function(match[1]);
assert(!v18.includes('v19-fotos.js') && !v18.includes('v19-relatorios.js'),
  'A versão V18 foi acidentalmente vinculada aos scripts V19.');
assert(html.includes('CAMPOS_EDICAO_CHAMADO'),'Permissões de edição ausentes.');
assert(html.includes('_slaHoras:'),'Prazo SLA bruto ausente do mapeamento.');
const migrations=[
 '00_diagnostico_integridade_estoque_somente_leitura.sql',
 '03_rpc_estoque_transacional_NAO_APLICAR.sql',
 '04_rls_estoque_isolamento_NAO_APLICAR.sql',
 '05_guard_garantia_e_historico_NAO_APLICAR.sql',
 '06_portal_configuracoes_NAO_APLICAR.sql'
];
for(const file of migrations){
 assert(existsSync('sql/v19/'+file),'Migration ausente: '+file);
}
console.log('✅ V19: JavaScript sintaticamente válido, arquivos e caminhos verificados.');
console.log('⚠️ Testes funcionais, permissões RLS e migrations ainda exigem homologação em Supabase separado.');
