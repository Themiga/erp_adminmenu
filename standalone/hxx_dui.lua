local CONFIG = {
    url = 'https://themiga.github.io/erp_adminmenu/',
    duiWidth = 1920,
    duiHeight = 1080,
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

local function safeCallNamed(name, fn, ...)
    if type(fn) ~= 'function' then
        debugLog(name .. ' unavailable')
        return false, nil
    end

    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        log(('ERROR | %s failed: %s'):format(name, tostring(a)))
        return false, nil
    end

    debugLog(name .. ' ok')
    return true, a, b, c
end

local function encode(payload)
    if json and type(json.encode) == 'function' then
        local ok, result = pcall(json.encode, payload)
        if ok then return result end
        log('ERROR | json.encode failed: ' .. tostring(result))
    end
    return nil
end

local function sendMessage(action, data)
    if not state.dui or state.destroyed then return end

    local payload = encode({ action = action, data = data })
    if not payload then return end

    local ok, err = pcall(SendDuiMessage, state.dui, payload)
    if ok then
        debugLog(('SendDuiMessage action=%s bytes=%d'):format(tostring(action), #payload))
    else
        log(('ERROR | SendDuiMessage %s failed: %s'):format(tostring(action), tostring(err)))
    end
end

local function releaseFocus()
    safeCallNamed('SetNuiFocusKeepInput(false)', SetNuiFocusKeepInput, false)
    safeCallNamed('SetNuiFocus(false,false)', SetNuiFocus, false, false)
end

local function setOpen(value)
    if not state.running or state.destroyed then return end

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
    if state.destroyed then return end

    log('cleanup starting: ' .. tostring(reason or 'no reason'))
    state.destroyed = true
    state.running = false
    state.open = false
    releaseFocus()

    if state.dui and type(DestroyDui) == 'function' then
        pcall(DestroyDui, state.dui)
        state.dui = nil
    end

    log('stopped')
end

local function getScreenResolution()
    if type(GetActiveScreenResolution) == 'function' then
        local ok, w, h = pcall(GetActiveScreenResolution)
        if ok and type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
            return w, h
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

    return drawW, drawH, 0.5 - drawW * 0.5, 0.5 - drawH * 0.5, sw, sh
end

local function getCursorNormalized()
    if type(GetNuiCursorPosition) == 'function' then
        local ok, x, y = pcall(GetNuiCursorPosition)
        if ok and type(x) == 'number' and type(y) == 'number' then
            local sw, sh = getScreenResolution()
            return x / sw, y / sh
        end
    end

    return GetControlNormal(0, 239), GetControlNormal(0, 240)
end

local function forwardMouse()
    if not state.dui then return end

    if type(SetMouseCursorActiveThisFrame) == 'function' then
        pcall(SetMouseCursorActiveThisFrame)
    end

    local nx, ny = getCursorNormalized()
    local drawW, drawH, left, top = getDrawRect()
    local lx = (nx - left) / drawW
    local ly = (ny - top) / drawH
    local inside = lx >= 0.0 and lx <= 1.0 and ly >= 0.0 and ly <= 1.0

    lx = math.max(0.0, math.min(1.0, lx))
    ly = math.max(0.0, math.min(1.0, ly))

    local x = math.floor(lx * (CONFIG.duiWidth - 1))
    local y = math.floor(ly * (CONFIG.duiHeight - 1))
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
    if type(RegisterNUICallback) ~= 'function' then return end

    RegisterNUICallback('close', function(_, cb)
        setOpen(false)
        cb({ ok = true })
    end)

    RegisterNUICallback('unload', function(_, cb)
        cb({ ok = true })
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
            coords = { x = coords.x, y = coords.y, z = coords.z },
            heading = GetEntityHeading(ped),
        })
    end)

    RegisterNUICallback('getVehicleInfo', function(_, cb)
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            cb({ ok = true, inVehicle = false })
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
    log('startup begin')
    debugLog(('url=%s dui=%dx%d'):format(CONFIG.url, CONFIG.duiWidth, CONFIG.duiHeight))

    pcall(registerCallbacks)

    local ok, duiOrErr = pcall(CreateDui, CONFIG.url, CONFIG.duiWidth, CONFIG.duiHeight)
    debugLog(('CreateDui pcall ok=%s result=%s type=%s'):format(tostring(ok), tostring(duiOrErr), type(duiOrErr)))
    if not ok or not duiOrErr then
        error('CreateDui failed: ' .. tostring(duiOrErr))
    end
    state.dui = duiOrErr

    if type(IsDuiAvailable) == 'function' then
        local startTimer = type(GetGameTimer) == 'function' and GetGameTimer() or 0
        local timeoutAt = startTimer + 15000
        local attempts = 0

        while state.running and not state.destroyed do
            attempts = attempts + 1
            local checkOk, result = pcall(IsDuiAvailable, state.dui)

            -- Some FiveM runtimes return 1/0 instead of Lua true/false.
            local available = checkOk and (
                result == true or
                (type(result) == 'number' and result ~= 0)
            )

            if attempts == 1 or attempts % 10 == 0 or available then
                debugLog(('IsDuiAvailable attempt=%d pcall=%s result=%s type=%s available=%s'):format(
                    attempts,
                    tostring(checkOk),
                    tostring(result),
                    type(result),
                    tostring(available)
                ))
            end

            if available then
                log(('DUI available after %d attempts'):format(attempts))
                break
            end

            if type(GetGameTimer) == 'function' and GetGameTimer() > timeoutAt then
                log(('DUI availability timeout after %d attempts; continuing'):format(attempts))
                break
            end

            Wait(100)
        end
    else
        Wait(1500)
    end

    local handleOk, handleOrErr = pcall(GetDuiHandle, state.dui)
    debugLog(('GetDuiHandle pcall ok=%s result=%s type=%s'):format(tostring(handleOk), tostring(handleOrErr), type(handleOrErr)))
    if not handleOk or not handleOrErr or tostring(handleOrErr) == '' then
        cleanup('missing DUI handle')
        return
    end
    state.duiHandle = handleOrErr

    local suffix = tostring(type(GetGameTimer) == 'function' and GetGameTimer() or math.random(10000, 99999))
    state.txdName = 'hxx_dui_txd_' .. suffix
    state.txnName = 'hxx_dui_tex_' .. suffix

    local txdOk, txdOrErr = pcall(CreateRuntimeTxd, state.txdName)
    debugLog(('CreateRuntimeTxd pcall ok=%s result=%s type=%s'):format(tostring(txdOk), tostring(txdOrErr), type(txdOrErr)))
    if not txdOk or not txdOrErr then
        cleanup('CreateRuntimeTxd failed')
        return
    end
    state.txd = txdOrErr

    local textureOk, textureOrErr = pcall(CreateRuntimeTextureFromDuiHandle, state.txd, state.txnName, state.duiHandle)
    debugLog(('CreateRuntimeTextureFromDuiHandle pcall ok=%s result=%s type=%s'):format(tostring(textureOk), tostring(textureOrErr), type(textureOrErr)))
    if not textureOk then
        cleanup('CreateRuntimeTextureFromDuiHandle failed')
        return
    end
    state.texture = textureOrErr

    log('runtime texture created')

    local resourceName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or nil
    CreateThread(function()
        for i = 1, 10 do
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

    log('started; use hxxdui in F8 or /hxxdui in chat')
end

RegisterCommand('hxxdui', function()
    log('/hxxdui invoked')
    setOpen(not state.open)
end, false)

RegisterCommand('hxxduiunload', function()
    log('/hxxduiunload invoked')
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

    debugLog('render loop entered')

    while state.running and not state.destroyed do
        Wait(0)

        if state.open and state.txdName and state.txnName then
            local drawW, drawH, _, _, sw, sh = getDrawRect()
            local drawOk, drawErr = pcall(
                DrawSprite,
                state.txdName,
                state.txnName,
                0.5,
                0.5,
                drawW,
                drawH,
                0.0,
                255,
                255,
                255,
                255
            )

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
end)

if type(AddEventHandler) == 'function' then
    AddEventHandler('onResourceStop', function(resourceName)
        if type(GetCurrentResourceName) == 'function' and resourceName == GetCurrentResourceName() then
            cleanup('resource stop')
        end
    end)
end

return {
    open = function() setOpen(true) end,
    close = function() setOpen(false) end,
    toggle = function() setOpen(not state.open) end,
    unload = function() cleanup('api unload') end,
    state = state,
}
