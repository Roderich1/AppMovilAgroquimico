// F03-RES-01 (#71): utilidades JSON mínimas sin jq. Lee JSON de stdin.
//   node json.cjs get <campo>     imprime un campo de primer nivel (para variables, no para la terminal)
//   node json.cjs keys            imprime las claves de primer nivel (seguro de mostrar)
//   node json.cjs ids             imprime los id de un arreglo (registros de cliente)
let input = '';
process.stdin.on('data', (chunk) => (input += chunk));
process.stdin.on('end', () => {
  const [mode, field] = process.argv.slice(2);
  let value;
  try {
    value = JSON.parse(input);
  } catch {
    console.log('<no-json>');
    return;
  }
  if (mode === 'get') {
    const out = value?.[field];
    if (out !== undefined && out !== null) process.stdout.write(String(out));
  } else if (mode === 'keys') {
    console.log(Object.keys(value ?? {}).sort().join(','));
  } else if (mode === 'ids') {
    const list = Array.isArray(value) ? value : (value?.items ?? value?.registrations ?? []);
    for (const item of list) {
      const id = item?.registrationId ?? item?.id;
      const status = item?.status ?? '';
      if (id) console.log(`${id} ${status}`);
    }
  }
});
