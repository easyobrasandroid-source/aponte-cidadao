const { chromium } = require('playwright');
const assert = require('node:assert/strict');

async function main() {
  const browser = await chromium.launch({headless:true});
  const page = await browser.newPage({viewport:{width:1280,height:800}});
  const errors = [];
  page.on('pageerror', e=>errors.push(e.message));
  try {
    const response = await page.goto('http://127.0.0.1:8765/',{waitUntil:'domcontentloaded',timeout:30000});
    assert.equal(response.status(),200,'HTML deve retornar HTTP 200');
    await page.locator('#loginEmail').waitFor({state:'visible',timeout:15000});
    assert(await page.locator('#loginSenha').isVisible(),'Campo senha visivel');
    assert(await page.locator('#btnLogin').isVisible(),'Botao entrar visivel');
    assert.equal(await page.locator('#loginSenha').getAttribute('type'),'password');
    console.log('PASS: interface de login carregada');

    await page.locator('#pg-login span[onclick*="pg-portal"]').click();
    await page.locator('#pg-portal').waitFor({state:'visible',timeout:10000});
    console.log('PASS: portal publico abriu');

    assert.equal(errors.length,0,'Excecoes JavaScript: '+errors.join(' | '));
    console.log('PASS: sem excecoes JavaScript durante os fluxos testados');
    console.log('PASS ALL: smoke test anonimo — nenhum dado modificado');
  } finally { await browser.close(); }
}
main().catch(e=>{console.error('FAIL:',e);process.exitCode=1;});