// Playwright, SOMENTE LEITURA: sem login e sem escrita no Supabase.
const { chromium } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const url = process.env.APP_URL || 'http://127.0.0.1:8765/';
const label = (process.env.TEST_LABEL || 'local').replace(/[^a-z0-9_-]/gi,'_');
const dest = path.resolve('testes/evidencias',label);
fs.mkdirSync(dest,{recursive:true});
const checks=[], jsErrors=[];
let browser,context,page,failure=null;
async function run(name,fn){
  try{await fn();checks.push({name,status:'PASS'});console.log('PASS:',name);}
  catch(e){checks.push({name,status:'FAIL',error:e.message});console.error('FAIL:',name,e.message);throw e;}
}
async function screenshot(name){
  await page.screenshot({path:path.join(dest,name+'.png'),fullPage:true,animations:'disabled'});
}
async function main(){
  browser=await chromium.launch({headless:true});
  context=await browser.newContext({
    viewport:{width:1280,height:800},
    recordVideo:{dir:dest,size:{width:1280,height:800}}
  });
  page=await context.newPage();
  page.setDefaultTimeout(12000);
  page.on('pageerror',e=>jsErrors.push(e.message));
  try{
    await run('Página responde HTTP 200',async()=>{
      const r=await page.goto(url,{waitUntil:'domcontentloaded',timeout:30000});
      assert.equal(r.status(),200);
    });
    await run('Login visível e senha protegida',async()=>{
      await page.locator('#loginEmail').waitFor({state:'visible'});
      assert(await page.locator('#btnLogin').isVisible());
      assert.equal(await page.locator('#loginSenha').getAttribute('type'),'password');
      await screenshot('01-login');
    });
    await run('Atalho Master preenche só e-mail',async()=>{
      await page.locator('#pg-login .lq[onclick*="master@aponte.test"]').click();
      assert.equal(await page.locator('#loginEmail').inputValue(),'master@aponte.test');
      assert.equal(await page.locator('#loginSenha').inputValue(),'');
      await screenshot('02-atalho-master');
    });
    await run('Portal público abre sem login',async()=>{
      await page.locator('#pg-login span[onclick*="pg-portal"]').click();
      await page.locator('#pg-portal').waitFor({state:'visible'});
      assert(await page.getByText('Relate um problema na iluminação pública').isVisible());
      await screenshot('03-portal');
    });
    await run('Consulta pública abre sem gravar chamado',async()=>{
      await page.locator('#pg-portal button[onclick*="pg-consulta"]').click();
      await page.locator('#pg-consulta').waitFor({state:'visible'});
      assert(await page.getByText('Consultar minha solicitação').isVisible());
      await screenshot('04-consulta');
    });
    await run('Voltar ao login',async()=>{
      await page.locator('#pg-consulta button[onclick*="pg-portal"]').click();
      await page.locator('#pg-portal').waitFor({state:'visible'});
      await page.locator('#pg-portal button[onclick*="pg-login"]').click();
      await page.locator('#pg-login').waitFor({state:'visible'});
    });
    await run('Layout mobile com largura 390px',async()=>{
      await page.setViewportSize({width:390,height:844});
      assert(await page.locator('#btnLogin').isVisible());
      await screenshot('05-login-celular');
    });
    await run('Sem exceções JavaScript nos fluxos testados',async()=>{
      assert.deepEqual(jsErrors,[]);
    });
  }catch(e){
    failure=String(e.stack||e);
    try{await screenshot('99-falha');}catch{}
  }finally{
    await page.close().catch(()=>{});
    await context.close().catch(()=>{});
    await browser.close().catch(()=>{});
    const passed=checks.filter(c=>c.status==='PASS').length;
    const result={url,executed_at:new Date().toISOString(),checks,passed,total:checks.length,
      success:!failure,js_errors:jsErrors,failure};
    fs.writeFileSync(path.join(dest,'resultado.json'),JSON.stringify(result,null,2));
    const report=[
      '# Aponte Cidadão — execução visual automática',
      '',
      'Alvo: '+url,
      'Resultado: '+(result.success?'APROVADO':'FALHOU')+' ('+passed+'/'+checks.length+')',
      '',
      '| Teste | Resultado |','|---|---|',
      ...checks.map(c=>'| '+c.name+' | '+c.status+' |'),
      '',
      'Evidências: arquivos PNG, vídeo WebM e resultado.json.',
      'Escopo: anônimo e somente leitura. Não comprova operações com login nem isolamento entre consórcios.',
      failure?'Falha: '+failure.slice(0,900):''
    ].join('\n');
    fs.writeFileSync(path.join(dest,'resumo.md'),report);
    console.log('RESULTADO:',result.success?'PASS ALL':'FAIL',passed+'/'+checks.length);
  }
  if(failure)process.exitCode=1;
}
main().catch(e=>{console.error(e);process.exitCode=1;});