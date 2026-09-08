local CONFIG = {
    url = 'https://themiga.github.io/erp_adminmenu/',
    duiWidth = 1920,
    duiHeight = 1080,
    openKey = 166, -- F5
    unloadKey = 167, -- F6
    debug = true,
    debugFrameIntervalMs = 2000,
}

local state = {
    running = true,
    open = false,
    destroyed = false,
    dui = nil,
    duiHandle = nil,
    txd = nil,
    txdName = nil,
    txnName = nil,
    texture = nil,
    mouseDownLeft = false,
    mouseDownRight = false,
    lastFrameLog = 0,
    drawCount = 0,
}

local function log(message)
    print(('[HXX DUI] %s'):format(tostring(message)))
end

local function debugLog(message)
    if CONFIG.debug then
        log('DEBUG | ' .. tostring(message))
    end
end

local function valueInfo(name, value)
    debugLog(('%s = %s (type=%s)'):format(name, tostring(value), type(value)))
end

local function safeCallNamed(name, fn, ...)
    if type(fn) ~= 'function' then
        debugLog(name .. ' unavailable (type=' .. type(fn) .. ')')
        return false, nil
    end

    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        log(('ERROR | %s failed: %s'):format(name, tostring(a)))
        return false, nil
    end

    debugLog(name .. ' ok')
    return true, a, b, c, d
end

local function safeCall(fn, ...)
    if type(fn) ~= 'function' then return false end
    return pcall(fn, ...)
end

local function encode(payload)
    if json and type(json.encode) == 'function' then
        local ok, result = pcall(json.encode, payload)
        if ok then return result end
        log('ERROR | json.encode failed: ' .. tostring(result))
    else
        debugLog('json.encode unavailable')
    end
    return nil
end

local function sendMessage(action, data)
    if not state.dui or state.destroyed then
        debugLog(('sendMessage(%s) skipped: dui=%s destroyed=%s'):format(tostring(action), tostring(state.dui), tostring(state.destroyed)))
        return
    end

    local payload = encode({action = action, data = data})
    if not payload then
        log('ERROR | could not encode DUI message: ' .. tostring(action))
        return
    end

    local ok, err = pcall(SendDuiMessage, state.dui, payload)
    if ok then
        debugLog(('SendDuiMessage action=%s bytes=%d'):format(tostring(action), #payload))
    else
        log(('ERROR | SendDuiMessage action=%s failed: %s'):format(tostring(action), tostring(err)))
    end
end

local function releaseFocus()
    safeCallNamed('SetNuiFocusKeepInput(false)', SetNuiFocusKeepInput, false)
    safeCallNamed('SetNuiFocus(false,false)', SetNuiFocus, false, false)
end

local function setOpen(value)
    if not state.running or state.destroyed then
        debugLog(('setOpen(%s) ignored: running=%s destroyed=%s'):format(tostring(value), tostring(state.running), tostring(state.destroyed)))
        return
    end

    state.open = value == true
    log('state.open = ' .. tostring(state.open))

    if state.open then
        safeCallNamed('SetNuiFocus(true,true)', SetNuiFocus, true, true)
        safeCallNamed('SetNuiFocusKeepInput(false)', SetNuiFocusKeepInput, false)
    else
        releaseFocus()
    end

    sendMessage('setVisible', state.open)
end

local function cleanup(reason)
    if state.destroyed then
        debugLog('cleanup skipped: already destroyed')
        return
    end

    log('cleanup starting: ' .. tostring(reason or 'no reason'))
    state.destroyed = true
    state.open = false
    state.running = false

    releaseFocus()

    if state.dui then
        local ok, err = pcall(DestroyDui, state.dui)
        if ok then
            debugLog('DestroyDui ok')
        else
            log('ERROR | DestroyDui failed: ' .. tostring(err))
        end
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
        debugLog(('GetActiveScreenResolution failed/invalid: ok=%s w=%s h=%s'):format(tostring(ok), tostring(width), tostring(height)))
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

    return drawW, drawH, left, top, sw, sh
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
    local moveOk, moveErr = pcall(SendDuiMouseMove, state.dui, x, y)
    if not moveOk then
        log('ERROR | SendDuiMouseMove failed: ' .. tostring(moveErr))
    end

    local leftPressed = IsDisabledControlJustPressed(0, 24) or IsControlJustPressed(0, 24)
    local leftReleased = IsDisabledControlJustReleased(0, 24) or IsControlJustReleased(0, 24)
    local rightPressed = IsDisabledControlJustPressed(0, 25) or IsControlJustPressed(0, 25)
    local rightReleased = IsDisabledControlJustReleased(0, 25) or IsControlJustReleased(0, 25)

    if inside and leftPressed and not state.mouseDownLeft then
        state.mouseDownLeft = true
        local ok, err = pcall(SendDuiMouseDown, state.dui, 'left')
        debugLog('mouse left down: ' .. tostring(ok) .. (ok and '' or (' err=' .. tostring(err))))
    end

    if leftReleased and state.mouseDownLeft then
        state.mouseDownLeft = false
        local ok, err = pcall(SendDuiMouseUp, state.dui, 'left')
        debugLog('mouse left up: ' .. tostring(ok) .. (ok and '' or (' err=' .. tostring(err))))
    end

    if inside and rightPressed and not state.mouseDownRight then
        state.mouseDownRight = true
        local ok, err = pcall(SendDuiMouseDown, state.dui, 'right')
        debugLog('mouse right down: ' .. tostring(ok) .. (ok and '' or (' err=' .. tostring(err))))
    end

    if rightReleased and state.mouseDownRight then
        state.mouseDownRight = false
        local ok, err = pcall(SendDuiMouseUp, state.dui, 'right')
        debugLog('mouse right up: ' .. tostring(ok) .. (ok and '' or (' err=' .. tostring(err))))
    end

    if inside then
        if IsDisabledControlJustPressed(0, 14) or IsControlJustPressed(0, 14) then
            pcall(SendDuiMouseWheel, state.dui, -120, 0)
            debugLog('mouse wheel down')
        elseif IsDisabledControlJustPressed(0, 15) or IsControlJustPressed(0, 15) then
            pcall(SendDuiMouseWheel, state.dui, 120, 0)
            debugLog('mouse wheel up')
        end
    end
end

local function registerCallbacks()
    debugLog('registerCallbacks begin')

    RegisterNUICallback('close', function(_, cb)
        debugLog('NUI callback: close')
        setOpen(false)
        cb({ok = true})
    end)

    RegisterNUICallback('unload', function(_, cb)
        debugLog('NUI callback: unload')
        cb({ok = true})
        CreateThread(function()
            Wait(50)
            cleanup('ui unload')
        end)
    end)

    RegisterNUICallback('getPlayerInfo', function(_, cb)
        debugLog('NUI callback: getPlayerInfo')
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
        debugLog('NUI callback: getVehicleInfo')
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

    debugLog('registerCallbacks complete')
end

local function dumpCapabilities()
    log('---- capability diagnostics ----')
    local names = {
        'CreateDui', 'IsDuiAvailable', 'GetDuiHandle', 'DestroyDui',
        'SendDuiMessage', 'SendDuiMouseMove', 'SendDuiMouseDown', 'SendDuiMouseUp', 'SendDuiMouseWheel',
        'CreateRuntimeTxd', 'CreateRuntimeTextureFromDuiHandle', 'DrawSprite',
        'SetNuiFocus', 'SetNuiFocusKeepInput', 'RegisterNUICallback',
        'RegisterCommand', 'RegisterKeyMapping', 'GetCurrentResourceName', 'GetActiveScreenResolution',
        'GetNuiCursorPosition', 'GetGameTimer'
    }

    for _, name in ipairs(names) do
        debugLog(name .. ' type=' .. type(_G[name]))
    end

    local resourceName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or '<nil>'
    debugLog('CurrentResourceName=' .. tostring(resourceName))

    local sw, sh = getScreenResolution()
    debugLog(('screen=%sx%s dui=%sx%s url=%s'):format(tostring(sw), tostring(sh), tostring(CONFIG.duiWidth), tostring(CONFIG.duiHeight), CONFIG.url))
    log('-------------------------------')
end

local function createHostedDui()
    log('startup begin')
    dumpCapabilities()

    local callbacksOk, callbacksErr = pcall(registerCallbacks)
    if not callbacksOk then
        log('ERROR | registerCallbacks failed: ' .. tostring(callbacksErr))
    end

    debugLog(('calling CreateDui(url=%s, w=%d, h=%d)'):format(CONFIG.url, CONFIG.duiWidth, CONFIG.duiHeight))
    local ok, duiOrErr = pcall(CreateDui, CONFIG.url, CONFIG.duiWidth, CONFIG.duiHeight)
    debugLog(('CreateDui pcall ok=%s result=%s resultType=%s'):format(tostring(ok), tostring(duiOrErr), type(duiOrErr)))

    if not ok or not duiOrErr then
        error('[HXX DUI] CreateDui failed: ' .. tostring(duiOrErr))
    end

    state.dui = duiOrErr
    valueInfo('state.dui', state.dui)

    if type(IsDuiAvailable) == 'function' then
        debugLog('waiting for IsDuiAvailable=true (timeout 15000ms)')
        local startTimer = type(GetGameTimer) == 'function' and GetGameTimer() or 0
        local timeoutAt = startTimer + 15000
        local attempts = 0

        while state.running and not state.destroyed do
            attempts = attempts + 1
            local checkOk, result = pcall(IsDuiAvailable, state.dui)
            local available = checkOk and result == true

            if attempts == 1 or attempts % 10 == 0 then
                debugLog(('IsDuiAvailable attempt=%d pcall=%s result=%s'):format(attempts, tostring(checkOk), tostring(result)))
            end

            if available then
                log(('DUI available after %d attempts'):format(attempts))
                break
            end

            if type(GetGameTimer) == 'function' and GetGameTimer() > timeoutAt then
                log(('DUI availability timeout after %d attempts; continuing with handle creation'):format(attempts))
                break
            end
            Wait(100)
        end
    else
        debugLog('IsDuiAvailable unavailable; waiting 1500ms fallback')
        Wait(1500)
    end

    debugLog('calling GetDuiHandle')
    local handleOk, handleOrErr = pcall(GetDuiHandle, state.dui)
    debugLog(('GetDuiHandle pcall ok=%s result=%s type=%s'):format(tostring(handleOk), tostring(handleOrErr), type(handleOrErr)))

    if not handleOk or not handleOrErr or tostring(handleOrErr) == '' then
        cleanup('missing DUI handle: ' .. tostring(handleOrErr))
        return
    end

    state.duiHandle = handleOrErr

    local suffix = tostring(type(GetGameTimer) == 'function' and GetGameTimer() or math.random(10000, 99999))
    state.txdName = 'hxx_dui_txd_' .. suffix
    state.txnName = 'hxx_dui_tex_' .. suffix

    debugLog('TXD name=' .. state.txdName)
    debugLog('TXN name=' .. state.txnName)

    local txdOk, txdOrErr = pcall(CreateRuntimeTxd, state.txdName)
    debugLog(('CreateRuntimeTxd pcall ok=%s result=%s type=%s'):format(tostring(txdOk), tostring(txdOrErr), type(txdOrErr)))
    if not txdOk or not txdOrErr then
        cleanup('CreateRuntimeTxd failed: ' .. tostring(txdOrErr))
        return
    end
    state.txd = txdOrErr

    local textureOk, textureOrErr = pcall(CreateRuntimeTextureFromDuiHandle, state.txd, state.txnName, state.duiHandle)
    debugLog(('CreateRuntimeTextureFromDuiHandle pcall ok=%s result=%s type=%s'):format(tostring(textureOk), tostring(textureOrErr), type(textureOrErr)))
    if not textureOk then
        cleanup('CreateRuntimeTextureFromDuiHandle failed: ' .. tostring(textureOrErr))
        return
    end
    state.texture = textureOrErr

    log('runtime texture created')

    local resourceName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or nil
    debugLog('bridge resourceName=' .. tostring(resourceName))

    CreateThread(function()
        for i = 1, 10 do
            if not state.running or state.destroyed then return end
            Wait(750)
            debugLog(('bridge heartbeat %d/10'):format(i))
            sendMessage('bridgeReady', {
                resourceName = resourceName,
                duiWidth = CONFIG.duiWidth,
                duiHeight = CONFIG.duiHeight,
            })
            sendMessage('setVisible', state.open)
        end
    end)

    log('started; use /hxxdui or F5 to toggle')
end

RegisterCommand('hxxdui', function()
    log('/hxxdui invoked')
    if state.running and not state.destroyed then
        setOpen(not state.open)
    else
        debugLog(('toggle ignored: running=%s destroyed=%s'):format(tostring(state.running), tostring(state.destroyed)))
    end
end, false)

RegisterCommand('hxxduiunload', function()
    log('/hxxduiunload invoked')
    cleanup('command unload')
end, false)

if type(RegisterKeyMapping) == 'function' then
    local ok1, err1 = pcall(RegisterKeyMapping, 'hxxdui', 'Toggle HXX hosted DUI', 'keyboard', 'F5')
    debugLog(('RegisterKeyMapping hxxdui ok=%s err=%s'):format(tostring(ok1), tostring(err1)))
    local ok2, err2 = pcall(RegisterKeyMapping, 'hxxduiunload', 'Unload HXX hosted DUI', 'keyboard', 'F6')
    debugLog(('RegisterKeyMapping hxxduiunload ok=%s err=%s'):format(tostring(ok2), tostring(err2)))
else
    debugLog('RegisterKeyMapping unavailable')
end

CreateThread(function()
    local ok, err = pcall(createHostedDui)
    if not ok then
        log('startup error: ' .. tostring(err))
        cleanup('startup failure')
        return
    end

    debugLog('render loop entered')

    while state.running and not state.destroyed do
        Wait(0)

        if state.open and state.txdName and state.txnName then
            local drawW, drawH, left, top, sw, sh = getDrawRect()

            local drawOk, drawErr = pcall(DrawSprite, state.txdName, state.txnName, 0.5, 0.5, drawW, drawH, 0.0, 255, 255, 255, 255)
            state.drawCount = state.drawCount + 1

            if not drawOk then
                log('ERROR | DrawSprite failed: ' .. tostring(drawErr))
            end

            local now = type(GetGameTimer) == 'function' and GetGameTimer() or 0
            if CONFIG.debug and (state.lastFrameLog == 0 or now - state.lastFrameLog >= CONFIG.debugFrameIntervalMs) then
                state.lastFrameLog = now
                debugLog(('render heartbeat drawCount=%d drawOk=%s txd=%s txn=%s rect=%.4fx%.4f screen=%sx%s'):format(
                    state.drawCount,
                    tostring(drawOk),
                    tostring(state.txdName),
                    tostring(state.txnName),
                    drawW,
                    drawH,
                    tostring(sw),
                    tostring(sh)
                ))
            end

            DisableControlAction(0, 1, true)
            DisableControlAction(0, 2, true)
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)

            forwardMouse()

            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                log('ESC detected; closing')
                setOpen(false)
            end
        end
    end

    debugLog('render loop exited')
end)

AddEventHandler('onResourceStop', function(resourceName)
    debugLog('onResourceStop event: ' .. tostring(resourceName))
    if type(GetCurrentResourceName) == 'function' and resourceName == GetCurrentResourceName() then
        cleanup('resource stop')
    end
end)

return {
    open = function()
        log('API open()')
        setOpen(true)
    end,
    close = function()
        log('API close()')
        setOpen(false)
    end,
    toggle = function()
        log('API toggle()')
        setOpen(not state.open)
    end,
    unload = function()
        log('API unload()')
        cleanup('api unload')
    end,
    state = state,
}
