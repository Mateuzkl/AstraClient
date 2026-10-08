-- Politica de credenciais; o protocolo TCP/RSA/XTEA nao e alterado.
ClientSecurity = {}

function ClientSecurity.isBrowser()
  return g_platform and g_platform.isBrowser and g_platform.isBrowser() or false
end

function ClientSecurity.canSendCredentials(url)
  if type(url) ~= 'string' or url:find('[%s%c]') then return false end
  local scheme, authority = url:match('^(%a[%w+.-]*)://([^/?#]+)')
  if not authority or authority:find('@', 1, true) or url:find('#', 1, true) then return false end
  scheme = scheme:lower()
  if scheme == 'https' then return true end
  if scheme ~= 'http' or ASTRA_ALLOW_LOCAL_HTTP_LOGIN ~= true then return false end
  local host = authority:lower():gsub(':%d+$', '')
  return host == 'localhost' or host == '127.0.0.1' or host == '[::1]'
end

function ClientSecurity.clearSavedCredentials()
  if not ClientSecurity.isBrowser() then return end
  for _, key in ipairs({'password', 'gtoken', 'ptoken', 'token', 'authenticatorToken',
      'sessionKey', 'accessToken', 'refreshToken', 'googleSession', 'autologin'}) do
    g_settings.remove(key)
  end
  g_settings.save()
end
