var vaultForgotten = false;
Module.astraCredentials = {
  available: () => true,
  get(scope) {
    if (scope !== '127.0.0.1:7171:860') throw new Error('wrong scope');
    return vaultForgotten ? '' : '{"account":"fixture","password":"synthetic"}';
  },
  save(scope, account, password) {
    if (scope !== '127.0.0.1:7171:860' || account !== 'fixture' || password !== 'synthetic')
      throw new Error('wrong bridge arguments');
    return !vaultForgotten;
  },
  forget() { vaultForgotten = true; },
  allowSaving() { vaultForgotten = false; }
};
