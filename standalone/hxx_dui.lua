local CONFIG = {
    url = 'https://themiga.github.io/erp_adminmenu/',
    duiWidth = 1920,
    duiHeight = 1080,
    openKey = 166, -- F5
    unloadKey = 167, -- F6
}

local state = {
    running = true,
    open = false,
    destroyed = false,
    dui = nil,
    txdName = nil,
    txnName = nil,
    mouseDownLeft = false,
    mouseDownRight = false,
}

local function log(message)
    print(('[HXX DUI] %s'):format(tostring(message)))
end

local function safeCall(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end

local function encode(payload)
    if json and type(json.encode) == 'function' then
        local ok, result = pcall(json.encode, payload)
        if ok then return result end
    end
    return nil
end

local function sendMessage(action, data)
    if not state.dui or state.destroyed then return end
    local payload = encode({action = action, data = data})
    if payload then
        pcall(SendDuiMessage, state.dui, payload)
    end
end

local function releaseFocus()
    safeCall(SetNuiFocusKeepInput, false)
    safeCall(SetNuiFocus, false, false)
end

local function setOpen(value)
    if not state.running or state.destroyed then return end
    state.open = value == true

    if state.open then
        safeCall(SetNuiFocus, true, true)
        safeCall(SetNuiFocusKeepInput, false)
    else
        releaseFocus()
    end

    sendMessage('setVisible', state.open)
end

local function cleanup(reason)
    if state.destroyed then return end
    state.destroyed = true
    state.open = false
    state.running = false

    releaseFocus()

    if state.dui then
        pcall(DestroyDui, state.dui)
        state.dui = nil
    end

    log(('stopped%s'):format(reason and (' (' .. tostring(reason) .. ')') or ''))
end

local function getScreenResolution()
    if type(GetActiveScreenResolution) == 'function' then
        local ok, width, height = pcall(GetActiveScreenResolution)
        if ok and type(width) == 'number' and type(height) == 'number' and width > 0 and height > 0 then
            return width, height
        end
    end
    return CONFIG.duiWidth, CONFIG.duiHeight
end

local function getDrawRect()
    local sw, sh = getScreenResolution()
    local screenAspect = sw / sh
    local duiAspect = CONFIG.duiWidth / CONFIG.duiHeight

    local drawW, drawH = 1.0, 1.0

    if screenAspect > duiAspect then
        drawW = duiAspect / screenAspect
    elseif screenAspect < duiAspect then
        drawH = screenAspect / duiAspect
    end

    local left = 0.5 - drawW * 0.5
    local top = 0.5 - drawH * 0.5

    return drawW, drawH, left, top
end

local function getCursorNormalized()
    if type(GetNuiCursorPosition) == 'function' then
        local ok, x, y = pcall(GetNuiCursorPosition)
        if ok and type(x) == 'number' and type(y) == 'number' then
            local sw, sh = getScreenResolution()
            if sw > 0 and sh > 0 then
                return x / sw, y / sh
            end
        end
    end

    local x = GetControlNormal(0, 239)
    local y = GetControlNormal(0, 240)
    return x, y
end

local function mapCursorToDui()
    local nx, ny = getCursorNormalized()
    local drawW, drawH, left, top = getDrawRect()

    local localX = (nx - left) / drawW
    local localY = (ny - top) / drawH
    local inside = localX >= 0.0 and localX <= 1.0 and localY >= 0.0 and localY <= 1.0

    localX = math.max(0.0, math.min(1.0, localX))
    localY = math.max(0.0, math.min(1.0, localY))

    return math.floor(localX * (CONFIG.duiWidth - 1)), math.floor(localY * (CONFIG.duiHeight - 1)), inside
end

local function forwardMouse()
    if not state.dui then return end

    safeCall(SetMouseCursorActiveThisFrame)

    local x, y, inside = mapCursorToDui()
    pcall(SendDuiMouseMove, state.dui, x, y)

    local leftPressed = IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24)
    local leftReleased = IsDisabledControlJustReleased(0, 24) or IsControlJustReleased(0, 24)
    local rightPressed = IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 25)
    local rightReleased = IsDisabledControlJustReleased(0, 25) or IsControlJustReleased(0, 25)

    if inside and leftPressed and not state.mouseDownLeft then
        state.mouseDownLeft = true
        pcall(SendDuiMouseDown, state.dui, 'left')
    end

    if leftReleased and state.mouseDownLeft then
        state.mouseDownLeft = false
        pcall(SendDuiMouseUp, state.dui, 'left')
    end

    if inside and rightPressed and not state.mouseDownRight then
        state.mouseDownRight = true
        pcall(SendDuiMouseDown, state.dui, 'right')
    end

    if rightReleased and state.mouseDownRight then
        state.mouseDownRight = false
        pcall(SendDuiMouseUp, state.dui, 'right')
    end

    if inside then
        if IsDisabledControlJustPressed(0, 14) or IsControlJustPressed(0, 14) then
            pcall(SendDuiMouseWheel, state.dui, -120, 0)
        elseif IsDisabledControlJustPressed(0, 15) or IsControlJustPressed(0, 15) then
            pcall(SendDuiMouseWheel, state.dui, 120, 0)
        end
    end
end

local function registerCallbacks()
    RegisterNUICallback('close', function(_, cb)
        setOpen(false)
        cb({ok = true})
    end)

    RegisterNUICallback('unload', function(_, cb)
        cb({ok = true})
        CreateThread(function()
            Wait(50)
            cleanup('ui unload')
        end)
    end)

    RegisterNUICallback('getPlayerInfo', function(_, cb)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)

        cb({
            ok = true,
            serverId = GetPlayerServerId(PlayerId()),
            health = GetEntityHealth(ped),
            armor = GetPedArmour(ped),
            coords = {x = coords.x, y = coords.y, z = coords.z},
            heading = GetEntityHeading(ped),
        })
    end)

    RegisterNUICallback('getVehicleInfo', function(_, cb)
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            cb({ok = true, inVehicle = false})
            return
        end

        local vehicle = GetVehiclePedIsIn(ped, false)
        local model = GetEntityModel(vehicle)

        cb({
            ok = true,
            inVehicle = true,
            model = model,
            displayName = GetDisplayNameFromVehicleModel(model),
            plate = GetVehicleNumberPlateText(vehicle),
            speed = GetEntitySpeed(vehicle) * 3.6,
        })
    end)
end

local function createHostedDui()
    registerCallbacks()

    local ok, dui = pcall(CreateDui, CONFIG.url, CONFIG.duiWidth, CONFIG.duiHeight)
    if not ok or not dui then
        error('[HXX DUI] CreateDui failed')
    end

    state.dui = dui

    if type(IsDuiAvailable) == 'function' then
        local timeoutAt = (type(GetGameTimer) == 'function' and GetGameTimer() or 0) + 15000
        while state.running and not state.destroyed do
            local available = false
            local checkOk, result = pcall(IsDuiAvailable, state.dui)
            available = checkOk and result == true
            if available then break end

            if type(GetGameTimer) == 'function' and GetGameTimer() > timeoutAt then
                log('DUI availability timeout; continuing with handle creation')
                break
            end
            Wait(100)
        end
    else
        Wait(1500)
    end

    local handle = GetDuiHandle(state.dui)
    if not handle then
        cleanup('missing DUI handle')
        return
    end

    local suffix = tostring(type(GetGameTimer) == 'function' and GetGameTimer() or math.random(10000, 99999))
    state.txdName = 'hxx_dui_txd_' .. suffix
    state.txnName = 'hxx_dui_tex_' .. suffix

    local txd = CreateRuntimeTxd(state.txdName)
    CreateRuntimeTextureFromDuiHandle(txd, state.txnName, handle)

    log('started')

    local resourceName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or nil

    CreateThread(function()
        for _ = 1, 6 do
            if not state.running or state.destroyed then return end
            Wait(750)
            sendMessage('bridgeReady', {
                resourceName = resourceName,
                duiWidth = CONFIG.duiWidth,
                duiHeight = CONFIG.duiHeight,
            })
            sendMessage('setVisible', state.open)
        end
    end)
end

RegisterCommand('hxxdui', function()
    if state.running and not state.destroyed then
        setOpen(not state.open)
    end
end, false)

RegisterCommand('hxxduiunload', function()
    cleanup('command unload')
end, false)

if type(RegisterKeyMapping) == 'function' then
    pcall(RegisterKeyMapping, 'hxxdui', 'Toggle HXX hosted DUI', 'keyboard', 'F5')
    pcall(RegisterKeyMapping, 'hxxduiunload', 'Unload HXX hosted DUI', 'keyboard', 'F6')
end

CreateThread(function()
    local ok, err = pcall(createHostedDui)
    if not ok then
        log('startup error: ' .. tostring(err))
        cleanup('startup failure')
        return
    end

    while state.running and not state.destroyed do
        Wait(0)

        if state.open and state.txdName and state.txnName then
            local drawW, drawH = getDrawRect()
            DrawSprite(state.txdName, state.txnName, 0.5, 0.5, drawW, drawH, 0.0, 255, 255, 255, 255)

            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)

            forwardMouse()

            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                setOpen(false)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if type(GetCurrentResourceName) == 'function' and resourceName == GetCurrentResourceName() then
        cleanup('resource stop')
    end
end)

return {
    open = function() setOpen(true) end,
    close = function() setOpen(false) end,
    toggle = function() setOpen(not state.open) end,
    unload = function() cleanup('api unload') end,
}
