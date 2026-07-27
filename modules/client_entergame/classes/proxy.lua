if not Proxy then
    Proxy = {
        host = "",
        port = 0,
        priority = 0,
    }
end

function Proxy:new(data)
    data = type(data) == "table" and data or {}
    local instance = setmetatable({}, { __index = self })
    instance.host = data.host or self.host
    instance.port = data.port or self.port
    instance.priority = data.priority or self.priority
    return instance
end

function Proxy:getPort()
    return self.port
end

function Proxy:getHost()
    return self.host
end
function Proxy:getPriority()
    return self.priority
end

function Proxy:setPort(port)
    self.port = port
end

if not Proxies then
    Proxies = {
        currentPort = 0,
        proxyList = {}
    }
end

function Proxies:loadProxyConfig(playerData)
    g_proxy.clear()
    self.currentPort = 0
    self.proxyList = {}
    if not playerData or not playerData["proxies"] then
        return
    end

    for _, proxyData in pairs(playerData["proxies"]) do
        local proxy = Proxy:new(proxyData)
        local host = proxy:getHost()
        local port = tonumber(proxy:getPort()) or 0
        local priority = tonumber(proxy:getPriority()) or 0
        if type(host) == "string" and host ~= "" and port > 0 then
            self.proxyList[host] = proxy
            self.currentPort = port
            g_proxy.addProxy(host, port, priority)
        end
    end
end

function Proxies:changePort(port)
    g_proxy.clear()
    for _, proxy in pairs(self.proxyList) do
        if type(proxy) == "table" and tonumber(port) and tonumber(port) > 0 then
            proxy:setPort(tonumber(port))
            g_proxy.addProxy(proxy:getHost(), proxy:getPort(), proxy:getPriority())
        end
    end
end

