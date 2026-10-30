// Testes estáticos e de elegibilidade do botão Assumir, sem Supabase e sem mutações.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const html = fs.readFileSync('index.html','utf8');
const sql = fs.readFileSync('sql/V18_01_assumir_chamado_empresa.sql','utf8');
const match = html.match(/function podeAssumirChamado\(c\)\{[\s\S]*?\n\}/);
assert(match, 'Não existe função podeAssumirChamado');
const eligible = new Function('CU','c',match[0]+'; return podeAssumirChamado(c);');
const tests = [
  [{perfil:'empresa',empresa_id:'minha-empresa'},{empresa_id:null,status:'Recebido',_supaId:'uuid'},true],
  [{perfil:'empresa',empresa_id:'minha-empresa'},{empresa_id:null,status:'Em programação',_supaId:'uuid'},true],
  [{perfil:'empresa',empresa_id:'minha-empresa'},{empresa_id:'outra-empresa',status:'Recebido',_supaId:'uuid'},false],
  [{perfil:'empresa',empresa_id:'minha-empresa'},{empresa_id:'minha-empresa',status:'Recebido',_supaId:'uuid'},false],
  [{perfil:'empresa',empresa_id:'minha-empresa'},{empresa_id:null,status:'Concluído',_supaId:'uuid'},false],
  [{perfil:'empresa',empresa_id:'minha-empresa'},{empresa_id:null,status:'Aguardando Garantia LED',_supaId:'uuid'},false],
  [{perfil:'consorcio',empresa_id:null},{empresa_id:null,status:'Recebido',_supaId:'uuid'},false],
  [{perfil:'prefeitura',empresa_id:null},{empresa_id:null,status:'Recebido',_supaId:'uuid'},false],
  [{perfil:'garantia',empresa_id:null},{empresa_id:null,status:'Recebido',_supaId:'uuid'},false],
  [{perfil:'empresa',empresa_id:null},{empresa_id:null,status:'Recebido',_supaId:'uuid'},false],
];
for(const [user,call,expected] of tests){
  assert.equal(Boolean(eligible(user,call)),expected,JSON.stringify({user,call,expected}));
}
assert(html.includes('rpc/assumir_chamado_empresa'), 'Front sem chamada RPC');
assert(html.includes('await carregarChamadosDoBanco()'), 'Front sem confirmação por nova leitura');
assert(sql.includes('CREATE POLICY pol_chamados_claim_empresa'),'RLS de assunção ausente');
assert(sql.includes('c.empresa_id IS NULL'),'UPDATE precisa exigir chamado livre');
assert(sql.includes('empresa_atende(c.cidade_id)'),'Validação da cobertura da cidade ausente');
assert(sql.includes('SECURITY INVOKER'),'Função não pode ignorar RLS');
assert(sql.includes("e.status='ativo'"),'Empresa inativa não está bloqueada');
assert(sql.includes('INSERT INTO public.chamado_historico'),'Histórico da assunção ausente');
console.log('PASS: 10 cenários de elegibilidade + 8 verificações do contrato de assunção');
