return function(GAME_CONFIG)
--------------------------------------------------------------------------------
-- ROOXHUB UI FRAMEWORK MODULE
-- File ini TIDAK perlu di-obfuscate. Hanya berisi UI generik/boilerplate.
-- Game logic dipanggil melalui callback yang didaftarkan via ctx:registerGame()
--------------------------------------------------------------------------------

GAME_CONFIG = GAME_CONFIG or {}
GAME_CONFIG.Name = GAME_CONFIG.Name or "Game Name"
GAME_CONFIG.Version = GAME_CONFIG.Version or "v 1.0.0"
GAME_CONFIG.Folder = GAME_CONFIG.Folder or "RooxHub_GameName"
GAME_CONFIG.GlobalFlag = GAME_CONFIG.GlobalFlag or "GameNameLoaded"
GAME_CONFIG.CleanupFlag = GAME_CONFIG.CleanupFlag or "GameNameCleanup"

--------------------------------------------------------------------------------
-- SERVICES
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local VirtualUser = game:GetService("VirtualUser")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() or Players.LocalPlayer
if not LocalPlayer then
    LocalPlayer = Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

--------------------------------------------------------------------------------
-- CLEANUP PREVIOUS INSTANCE
--------------------------------------------------------------------------------
if getgenv()[GAME_CONFIG.CleanupFlag] then
    pcall(getgenv()[GAME_CONFIG.CleanupFlag])
end
getgenv()[GAME_CONFIG.GlobalFlag] = false

pcall(function()
    local function purgeOldGuis(parent)
        if not parent then return end
        for _, c in ipairs(parent:GetChildren()) do
            if c:IsA("ScreenGui") and (c.Name:find("WindUI") or c.Name:find("Roox") or c:FindFirstChild("Roox_DarkRedGradientBG", true) or c:FindFirstChild("Roox_DarkBlueGradientBG", true)) then
                pcall(function() c:Destroy() end)
            end
        end
    end
    purgeOldGuis(CoreGui:FindFirstChild("RobloxGui"))
    purgeOldGuis(CoreGui)
    if gethui then purgeOldGuis(gethui()) end
    if LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui") then purgeOldGuis(LocalPlayer.PlayerGui) end
end)

getgenv()[GAME_CONFIG.GlobalFlag] = true

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------
local DISCORD_INVITE = "https://discord.gg/GK6EAEzrZK"
local customLogo = "rbxassetid://72595419713638"

--------------------------------------------------------------------------------
-- UTILITIES
--------------------------------------------------------------------------------
local function copyToClipboard(text)
    local copied = false
    if setclipboard then pcall(function() setclipboard(text) copied = true end) end
    if not copied and toclipboard then pcall(function() toclipboard(text) copied = true end) end
    if not copied and typeof(Clipboard) == "table" and Clipboard.set then pcall(function() Clipboard.set(text) copied = true end) end
    if not copied and set_clipboard then pcall(function() set_clipboard(text) copied = true end) end
    if not copied and writeclipboard then pcall(function() writeclipboard(text) copied = true end) end
    return copied
end

local function getHttpRequest()
    return (getgenv and (getgenv().request or getgenv().http_request)) or request or http_request or (syn and syn.request) or (http and http.request) or (fluxus and fluxus.request)
end

local function safeFireServer(remote, ...)
    pcall(function(...) remote:FireServer(...) end, ...)
end

--------------------------------------------------------------------------------
-- CONFIG, STATS, FLAGS, CONNECTIONS, UIELEMENTS
--------------------------------------------------------------------------------
local Config = {
    AntiAFKInterval = 60,
    WebhookEnabled = false,
    WebhookUrl = "",
    WebhookPing = false,
    WebhookUserId = "",

    -- FPS Boost (Settings tab). The boost LOGIC lives in the game module;
    -- the template only stores the on/off state and draws the 2 toggles.
    -- See the "FPS BOOST HOOK" comment near ctx.boost below.
    BoostUltra = false,
    BoostNoEffects = false,
}

local Stats = {}
local Flags = {
    AntiAFK = false,
}

local Connections = {}
local UIElements = {}

--------------------------------------------------------------------------------
-- WEBHOOK SYSTEM
--------------------------------------------------------------------------------
local function sendWebhook(url, payload, pingText)
    if not url or url == "" then return false, "Webhook URL is empty." end

    url = url:match("^%s*(.-)%s*$")
    if not url:find("discord") or not url:find("/api/webhooks/") then
        return false, "Not a valid Discord Webhook URL. Format must be: https://discord.com/api/webhooks/..."
    end

    local httpReq = getHttpRequest()
    if not httpReq then
        return false, "Executor does not support HTTP request (request / http_request not found)."
    end

    if pingText and pingText ~= "" then
        payload.content = pingText
    end

    local jsonBody = HttpService:JSONEncode(payload)

    local okSend, resSend = pcall(function()
        return httpReq({
            Url = url,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
            },
            Body = jsonBody,
        })
    end)

    if okSend and resSend then
        local statusCode = resSend.StatusCode or resSend.status_code
        if statusCode == 200 or statusCode == 204 then
            return true, "Webhook sent successfully!"
        else
            local errBody = resSend.Body and tostring(resSend.Body) or ""
            return false, "Discord error (" .. tostring(statusCode) .. "): " .. errBody:sub(1, 120)
        end
    end
    return false, "HTTP request failed: " .. tostring(resSend or "Unknown error")
end

local function buildEmbed(opts)
    local playerAvatarUrl = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. tostring(LocalPlayer.UserId) .. "&width=150&height=150&format=png"
    local embed = {
        title = opts.title or "Notification",
        description = opts.description or nil,
        color = opts.color or 2001125,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        author = opts.author or {
            name = LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")",
            icon_url = playerAvatarUrl,
        },
        fields = opts.fields or {},
        footer = opts.footer or {
            text = "RooxHub • " .. GAME_CONFIG.Name .. " | Discord: " .. DISCORD_INVITE,
        },
    }
    if opts.thumbnail then
        embed.thumbnail = { url = opts.thumbnail }
    end
    if opts.image then
        embed.image = { url = opts.image }
    end
    return embed
end

local function sendTestWebhook()
    local rawUrl = Config.WebhookUrl
    if not rawUrl or rawUrl == "" then
        return false, "Enter the Webhook URL first!"
    end

    local pingText = ""
    if Config.WebhookPing and Config.WebhookUserId and Config.WebhookUserId ~= "" then
        pingText = "<@" .. tostring(Config.WebhookUserId):gsub("%D", "") .. ">"
    end

    local testEmbed
    if _gameCallbacks and _gameCallbacks.onTestWebhook then
        testEmbed = _gameCallbacks.onTestWebhook(buildEmbed)
    end
    if not testEmbed then
        testEmbed = buildEmbed({
            title = "🧪 TEST WEBHOOK • " .. GAME_CONFIG.Name,
            description = "Discord embed test sent successfully!",
            color = 65280,
            fields = {
                { name = "👤 Player", value = LocalPlayer.Name .. " (@" .. LocalPlayer.DisplayName .. ")", inline = false },
                { name = "🎮 Game", value = GAME_CONFIG.Name .. " " .. GAME_CONFIG.Version, inline = false },
            },
        })
    end

    return sendWebhook(rawUrl, { embeds = { testEmbed } }, pingText)
end

--------------------------------------------------------------------------------
-- WINDUI LOAD + THEME
--------------------------------------------------------------------------------
local WindUI
do
    local WINDUI_URLS = {
        "https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua",
        "https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua",
        "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua",
    }
    local CACHE_PATH = "WindUI_cached.lua"
    local src
    for _, url in ipairs(WINDUI_URLS) do
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and type(res) == "string" and #res > 1000 and not res:find("<!DOCTYPE") and not res:find("<html>") then
            src = res
            pcall(function() writefile(CACHE_PATH, src) end)
            break
        end
    end
    if not src then
        pcall(function()
            if isfile(CACHE_PATH) then src = readfile(CACHE_PATH) end
        end)
    end
    if not src or #src < 1000 then
        error("[RooxHub] Failed to load WindUI from all sources. Check your internet connection.")
    end
    WindUI = loadstring(src)()
end

pcall(function()
    WindUI:AddTheme({
        Name = "ObsidianBlue",
        Accent = Color3.fromRGB(35, 100, 215),
        Background = Color3.fromRGB(10, 12, 16),
        Dialog = Color3.fromRGB(14, 16, 22),
        ElementBackground = Color3.fromRGB(16, 20, 28),
        ElementBackgroundTransparency = 0.35,
        Icon = Color3.fromRGB(180, 205, 235),
        LabelBackground = Color3.fromRGB(8, 10, 14),
        LabelBackgroundTransparency = 0.7,
        Outline = Color3.fromRGB(25, 45, 85),
        PanelBackground = Color3.fromRGB(14, 18, 25),
        PanelBackgroundTransparency = 0.5,
        Placeholder = Color3.fromRGB(100, 120, 150),
        Primary = Color3.fromRGB(35, 100, 215),
        Slider = Color3.fromRGB(35, 100, 215),
        SliderIcon = Color3.fromRGB(190, 215, 240),
        Text = Color3.fromRGB(250, 252, 255),
        Toggle = Color3.fromRGB(35, 100, 215),
    })
end)

local Window = WindUI:CreateWindow({
    Title = "RooxHub",
    Author = GAME_CONFIG.Name .. " • " .. GAME_CONFIG.Version,
    Icon = "sparkles",
    Folder = GAME_CONFIG.Folder,
    Size = UDim2.fromOffset(630, 500),
    Transparent = false,
    Theme = "ObsidianBlue",
    Resizable = true,
    SideBarWidth = 200,
    HideSearchBar = false,
    ScrollBarEnabled = true,
    IgnoreAlerts = true,
    User = {
        Enabled = true,
        Anonymous = false,
        Callback = function()
            copyToClipboard(DISCORD_INVITE)
        end,
    },
    OpenButton = {
        Title = "", Icon = "sparkles",
        CornerRadius = UDim.new(0, 12), StrokeThickness = 2,
        Color = ColorSequence.new(Color3.fromRGB(10, 12, 16), Color3.fromRGB(20, 50, 110)),
        OnlyMobile = false, Enabled = true, Draggable = false, OnlyIcon = true,
    },
})

--------------------------------------------------------------------------------
-- UI CUSTOMIZATIONS
--------------------------------------------------------------------------------
pcall(function()
    local main = Window.UIElements and Window.UIElements.Main
    if not main then return end
    local bgGrad = Instance.new("Frame")
    bgGrad.Name = "Roox_DarkBlueGradientBG"
    bgGrad.Size = UDim2.new(1, 0, 1, 0)
    bgGrad.ZIndex = 0
    bgGrad.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    bgGrad.BorderSizePixel = 0
    Instance.new("UICorner", bgGrad).CornerRadius = UDim.new(0, 16)
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.0, Color3.fromRGB(10, 12, 16)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(12, 18, 28)),
        ColorSequenceKeypoint.new(1.0, Color3.fromRGB(18, 38, 70))
    })
    grad.Rotation = 135
    grad.Parent = bgGrad
    bgGrad.Parent = main
    local defaultBg = main:FindFirstChild("Background")
    if defaultBg then defaultBg.ImageTransparency = 0.65 defaultBg.ImageColor3 = Color3.fromRGB(10, 18, 30) end
end)

local rootGui = nil
pcall(function()
    if Window.UIElements and Window.UIElements.Main then rootGui = Window.UIElements.Main:FindFirstAncestorWhichIsA("ScreenGui") end
    if not rootGui and Window.ScreenGui then rootGui = Window.ScreenGui end
end)

pcall(function()
    if not rootGui then return end
    for _, desc in ipairs(rootGui:GetDescendants()) do
        if desc.Name == "Left" and desc:IsA("Frame") and desc.Parent and desc.Parent.Name == "Topbar" then
            local img = desc:FindFirstChildWhichIsA("ImageLabel", true)
            if img and customLogo then
                img.Image = customLogo
                img.ImageColor3 = Color3.new(1, 1, 1)
                img.ImageRectSize = Vector2.new(0, 0)
                img.ImageRectOffset = Vector2.new(0, 0)
            end
        elseif desc.Name == "TextButton" and desc:IsA("TextButton") and desc.Parent and desc.Parent.Name == "Frame" and desc.Parent.Parent and desc.Parent.Parent.Name == "Frame" and desc.Parent.Parent.Parent and desc.Parent.Parent.Parent.Name == "Window" then
            local openContainer = desc.Parent
            local dragFrame = openContainer:FindFirstChild("Drag")
            local sepFrame = openContainer:FindFirstChild("Frame")
            local textLabel = desc:FindFirstChild("TextLabel")
            local iconFrame = desc:FindFirstChild("Frame")
            local img = iconFrame and iconFrame:FindFirstChildWhichIsA("ImageLabel", true)

            if dragFrame then dragFrame.Visible = false end
            if sepFrame then sepFrame.Visible = false end
            if textLabel then textLabel.Visible = false end

            local c1 = openContainer:FindFirstChild("UICorner")
            if c1 then c1.CornerRadius = UDim.new(0, 12) end
            local c2 = desc:FindFirstChild("UICorner")
            if c2 then c2.CornerRadius = UDim.new(0, 10) end

            local pad = desc:FindFirstChild("UIPadding")
            if pad then
                pad.PaddingLeft = UDim.new(0, 4)
                pad.PaddingRight = UDim.new(0, 4)
                pad.PaddingTop = UDim.new(0, 4)
                pad.PaddingBottom = UDim.new(0, 4)
            end

            if iconFrame then
                iconFrame.Size = UDim2.new(0, 32, 0, 32)
            end

            if img then
                if customLogo then
                    img.Image = customLogo
                    img.ImageColor3 = Color3.new(1, 1, 1)
                    img.ImageRectSize = Vector2.new(0, 0)
                    img.ImageRectOffset = Vector2.new(0, 0)
                end
                local imgCorner = img:FindFirstChild("UICorner")
                if not imgCorner then
                    imgCorner = Instance.new("UICorner")
                    imgCorner.CornerRadius = UDim.new(0, 8)
                    imgCorner.Parent = img
                else
                    imgCorner.CornerRadius = UDim.new(0, 8)
                end
            end

            local dragging = false
            local dragInput, mousePos, framePos
            desc.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    mousePos = input.Position
                    framePos = openContainer.Position
                    input.Changed:Connect(function()
                        if input.UserInputState == Enum.UserInputState.End then
                            dragging = false
                        end
                    end)
                end
            end)
            desc.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    dragInput = input
                end
            end)
            UserInputService.InputChanged:Connect(function(input)
                if input == dragInput and dragging then
                    local delta = input.Position - mousePos
                    if delta.Magnitude > 3 then
                        openContainer.Position = UDim2.new(framePos.X.Scale, framePos.X.Offset + delta.X, framePos.Y.Scale, framePos.Y.Offset + delta.Y)
                    end
                end
            end)
        end
    end
end)

local topbarRight, userBtn = nil, nil
if rootGui then
    for _, desc in ipairs(rootGui:GetDescendants()) do
        if desc.Name == "Right" and desc:IsA("Frame") and desc.Parent and desc.Parent.Name == "Topbar" then topbarRight = desc
        elseif desc.Name == "UserIcon" and desc.Parent and desc.Parent:IsA("TextButton") then userBtn = desc.Parent end
    end
end

local fpsLabel = nil
if topbarRight then
    local fpsBadge = Instance.new("Frame")
    fpsBadge.Name = "Roox_FPSBadge"
    fpsBadge.Size = UDim2.new(0, 74, 0, 26)
    fpsBadge.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
    fpsBadge.BackgroundTransparency = 0.2
    fpsBadge.LayoutOrder = -1
    Instance.new("UICorner", fpsBadge).CornerRadius = UDim.new(0, 6)
    local bStroke = Instance.new("UIStroke") bStroke.Color = Color3.fromRGB(25, 50, 95) bStroke.Thickness = 1 bStroke.Parent = fpsBadge
    fpsLabel = Instance.new("TextLabel")
    fpsLabel.Name = "FPSText" fpsLabel.Size = UDim2.new(1, 0, 1, 0) fpsLabel.BackgroundTransparency = 1
    fpsLabel.Text = "60 FPS" fpsLabel.TextColor3 = Color3.fromRGB(180, 205, 235)
    fpsLabel.TextSize = 12 fpsLabel.Font = Enum.Font.GothamBold fpsLabel.Parent = fpsBadge
    fpsBadge.Parent = topbarRight
end

if userBtn and userBtn.Parent then
    local discordBtn = Instance.new("TextButton")
    discordBtn.Name = "Roox_JoinDiscordBtn" discordBtn.Size = UDim2.new(0, 186, 0, 32)
    discordBtn.Position = UDim2.new(0, 7, 1, -68) discordBtn.AnchorPoint = Vector2.new(0, 1)
    discordBtn.BackgroundColor3 = Color3.fromRGB(20, 48, 105) discordBtn.Text = "JOIN DISCORD"
    discordBtn.TextColor3 = Color3.fromRGB(255, 255, 255) discordBtn.Font = Enum.Font.GothamBold
    discordBtn.TextSize = 12 discordBtn.AutoButtonColor = true
    Instance.new("UICorner", discordBtn).CornerRadius = UDim.new(0, 8)
    local dStroke = Instance.new("UIStroke") dStroke.Color = Color3.fromRGB(35, 75, 150) dStroke.Thickness = 1 dStroke.Parent = discordBtn
    discordBtn.MouseButton1Click:Connect(function()
        copyToClipboard(DISCORD_INVITE)
        WindUI:Notify({ Title = "RooxHub • Discord", Content = "Discord link copied to clipboard.", Duration = 3 })
    end)
    discordBtn.Parent = userBtn.Parent
end

local function fixSidebarLayout()
    pcall(function()
        local g = gethui and gethui() or game:GetService("CoreGui")
        local btn, sf = nil, nil
        for _, d in ipairs(g:GetDescendants()) do
            if d.Name == "Roox_JoinDiscordBtn" then btn = d end
            if d:IsA("ScrollingFrame") and d.Parent and d.Parent.Parent and d.Parent.Parent.Name == "Main" then sf = d end
        end
        if not btn or not sf then return end
        local parent = sf.Parent
        parent.Size = UDim2.new(0, 200, 1, -170)
        local pad = sf:FindFirstChildWhichIsA("UIPadding")
        if pad then pad.PaddingBottom = UDim.new(0, 16) end
    end)
end
task.delay(0.5, fixSidebarLayout)
task.delay(1.5, fixSidebarLayout)

--------------------------------------------------------------------------------
-- FPS COUNTER
--------------------------------------------------------------------------------
local COLOR_FPS_GOOD = Color3.fromRGB(0, 255, 160)
local COLOR_FPS_WARN = Color3.fromRGB(255, 200, 50)
local COLOR_FPS_BAD = Color3.fromRGB(255, 80, 80)

local frameAccum, timeAccum, lastDisplayFps = 0, 0, -1
pcall(function()
    Connections.FPSCounter = RunService.RenderStepped:Connect(function(dt)
        frameAccum = frameAccum + 1
        timeAccum = timeAccum + ((type(dt) == "number" and dt > 0.0001 and dt < 1) and dt or 0.0166)
        if timeAccum >= 0.5 then
            local fps = math.floor((frameAccum / timeAccum) + 0.5)
            frameAccum = 0
            timeAccum = 0
            if fpsLabel and fpsLabel.Parent and fps ~= lastDisplayFps then
                lastDisplayFps = fps
                fpsLabel.Text = " " .. tostring(math.clamp(fps, 1, 360)) .. " FPS"
                fpsLabel.TextColor3 = fps >= 50 and COLOR_FPS_GOOD or fps >= 30 and COLOR_FPS_WARN or COLOR_FPS_BAD
            end
        end
    end)
end)

--------------------------------------------------------------------------------
-- UI STATE HELPERS
--------------------------------------------------------------------------------
local function setUIElementVisual(element, val)
    if not element then return end
    pcall(function()
        if typeof(element.Set) == "function" then
            element:Set(val)
        elseif typeof(element.Select) == "function" then
            element:Select(val)
        end
    end)
end

local function invokeUIElementCallback(element, val)
    if not element then return end
    pcall(function()
        if (element.Type == "Toggle" or element.__type == "Toggle") and typeof(element.Callback) == "function" then
            task.spawn(function()
                pcall(element.Callback, val)
            end)
        end
    end)
end

local function safeUpdateDropdown(dropdown, values)
    if not dropdown then return end
    pcall(function()
        if dropdown.SetValues then
            dropdown:SetValues(values)
        elseif dropdown.Refresh then
            dropdown:Refresh(values, true)
        end
    end)
end

--------------------------------------------------------------------------------
-- CONFIG SAVE/LOAD SYSTEM
--------------------------------------------------------------------------------
local CONFIG_DIR = GAME_CONFIG.Folder .. "/Configs"
local SETTINGS_FILE = GAME_CONFIG.Folder .. "/_settings.json"

local SystemSettings = {
    AutoExecuteConfig = false,
    LastConfigName = "default",
}

local function saveSystemSettings()
    pcall(function()
        if not isfolder(GAME_CONFIG.Folder) then makefolder(GAME_CONFIG.Folder) end
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        writefile(SETTINGS_FILE, HttpService:JSONEncode(SystemSettings))
    end)
end

local function loadSystemSettings()
    pcall(function()
        if isfile(SETTINGS_FILE) then
            local data = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            if typeof(data) == "table" then
                for k, v in pairs(data) do
                    SystemSettings[k] = v
                end
                if data.AutoLoadExeConfig or data.AutoExecuteLastConfig then
                    SystemSettings.AutoExecuteConfig = true
                end
            end
        end
    end)
end

local function getSavedConfigsList()
    local list = {}
    pcall(function()
        if not isfolder(GAME_CONFIG.Folder) then makefolder(GAME_CONFIG.Folder) end
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        local files = listfiles(CONFIG_DIR)
        for _, f in ipairs(files) do
            local name = f:match("([^\\/]+)%.json$")
            if name and name ~= "_settings" then
                table.insert(list, name)
            end
        end
    end)
    if #list == 0 then
        table.insert(list, "default")
    end
    table.sort(list)
    return list
end

local _gameCallbacks = nil

local function exportConfigTable()
    local data = {
        _gameId = GAME_CONFIG.Folder,
        _gameName = GAME_CONFIG.Name,
        Flags = Flags,
        Config = Config,
    }

    if _gameCallbacks and _gameCallbacks.onExport then
        _gameCallbacks.onExport(data)
    end

    return data
end

local CONFIG_APPLY_STEP = 0.15
local configApplyGen = 0

local function applyConfig(tbl)
    if typeof(tbl) ~= "table" then return false end

    if tbl._gameId and tbl._gameId ~= GAME_CONFIG.Folder then
        return false, "wrong_game"
    end

    configApplyGen = configApplyGen + 1
    local gen = configApplyGen
    local queue = {}

    if tbl.Flags and typeof(tbl.Flags) == "table" then
        for k, v in pairs(tbl.Flags) do
            if Flags[k] ~= nil then
                Flags[k] = v
                if UIElements[k] then
                    table.insert(queue, { element = UIElements[k], value = v })
                end
            end
        end
    end

    if tbl.Config and typeof(tbl.Config) == "table" then
        for k, v in pairs(tbl.Config) do
            if Config[k] ~= nil then
                Config[k] = v
                if UIElements[k] then
                    table.insert(queue, { element = UIElements[k], value = v })
                end
            end
        end
    end

    if _gameCallbacks and _gameCallbacks.onApply then
        _gameCallbacks.onApply(tbl, queue)
    end

    task.spawn(function()
        for _, op in ipairs(queue) do
            if gen ~= configApplyGen then return end
            setUIElementVisual(op.element, op.value)
            task.wait(CONFIG_APPLY_STEP)
            if gen ~= configApplyGen then return end
            invokeUIElementCallback(op.element, op.value)
            task.wait(CONFIG_APPLY_STEP)
        end
    end)

    return true
end

local function saveConfigFile(name)
    if not name or name == "" then name = "default" end
    name = name:gsub("[^%w_%-]", "")
    if name == "" then name = "default" end

    local data = exportConfigTable()
    local json = HttpService:JSONEncode(data)
    local success = pcall(function()
        if not isfolder(GAME_CONFIG.Folder) then makefolder(GAME_CONFIG.Folder) end
        if not isfolder(CONFIG_DIR) then makefolder(CONFIG_DIR) end
        writefile(CONFIG_DIR .. "/" .. name .. ".json", json)
    end)

    if success then
        SystemSettings.LastConfigName = name
        saveSystemSettings()
    end
    return success, name
end

local function loadConfigFile(name)
    if not name or name == "" then name = "default" end
    name = name:gsub("[^%w_%-]", "")
    local path = CONFIG_DIR .. "/" .. name .. ".json"

    local loaded = false
    local rejected = false
    pcall(function()
        if isfile(path) then
            local json = readfile(path)
            local data = HttpService:JSONDecode(json)
            if typeof(data) == "table" then
                if data._gameId and data._gameId ~= GAME_CONFIG.Folder then
                    rejected = true
                    return
                end
                applyConfig(data)
                SystemSettings.LastConfigName = name
                saveSystemSettings()
                loaded = true
            end
        end
    end)
    if rejected then
        pcall(function()
            WindUI:Notify({
                Title = "RooxHub • Configs",
                Content = "Config '" .. name .. "' ditolak! Config ini milik game lain.",
                Duration = 4,
            })
        end)
    end
    return loaded
end

local function deleteConfigFile(name)
    if not name or name == "" then return false end
    name = name:gsub("[^%w_%-]", "")
    local path = CONFIG_DIR .. "/" .. name .. ".json"
    local deleted = false
    pcall(function()
        if isfile(path) then
            delfile(path)
            deleted = true
        end
    end)
    return deleted
end

--------------------------------------------------------------------------------
-- PROTECTION (ANTI-AFK) -- inlined, no external module
-- Ported from RooxHub_Protection.lua. The FPS Boost part was removed on purpose:
-- that logic now lives in the game module (see the FPS BOOST HOOK comment below).
--------------------------------------------------------------------------------
local Protection = (function()
    local M = {}

    -- ======================= ANTI-AFK =======================
    -- Layered anti-AFK that works on PC and mobile executors (Delta, Arceus, ...).
    --  Layer 1 generic : kill the game's AFK LocalScript + all Idled connections.
    --  Layer 2 generic : real input replay (VirtualUser + firesignal where supported).
    --  Layer 3 per-game: override M.applyGameSpecificAFK from the game module if the
    --                    game stores its own AFK timeout somewhere (attribute, etc.).
    local afkState = {
        enabled = false,
        running = false,
        thread = nil,
        idledConn = nil,
    }

    local function disableIdledConnections()
        pcall(function()
            if not getconnections then return end
            local conns = getconnections(LocalPlayer.Idled)
            if not conns then return end
            for _, conn in ipairs(conns) do
                if conn.Disable then
                    pcall(function() conn:Disable() end)
                elseif conn.Disconnect then
                    pcall(function() conn:Disconnect() end)
                end
            end
        end)
    end

    function M.bypassGameAFK()
        pcall(function()
            local ps = LocalPlayer:FindFirstChild("PlayerScripts")
            local afk = ps and ps:FindFirstChild("AFK")
            if afk then
                pcall(function() afk.Disabled = true end)
                pcall(function() afk:Destroy() end)
            end
        end)
        pcall(function()
            if not Connections.AFKWatcher and LocalPlayer:FindFirstChild("PlayerScripts") then
                Connections.AFKWatcher = LocalPlayer.PlayerScripts.ChildAdded:Connect(function(child)
                    if child.Name == "AFK" and child:IsA("LocalScript") then
                        child.Disabled = true
                        child:Destroy()
                    end
                end)
            end
        end)
        disableIdledConnections()
    end

    -- Game-specific AFK hook. Default no-op; override it from your game module, e.g.:
    --   ctx.Protection.applyGameSpecificAFK = function()
    --       workspace:SetAttribute("TestAfk", 1e9)  -- Ride A Pet style
    --   end
    function M.applyGameSpecificAFK() end

    local function fakeInputObject()
        return {
            UserInputType = Enum.UserInputType.MouseButton1,
            UserInputState = Enum.UserInputState.Begin,
            KeyCode = Enum.KeyCode.Unknown,
            Position = Vector3.new(1, 1, 1),
            Delta = Vector3.new(1, 1, 1),
        }
    end

    local function replayInput()
        if typeof(firesignal) ~= "function" then return end
        pcall(function() firesignal(UserInputService.InputBegan, fakeInputObject()) end)
        pcall(function() firesignal(UserInputService.InputChanged, fakeInputObject()) end)
        pcall(function() firesignal(UserInputService.InputEnded, fakeInputObject()) end)
        pcall(function() firesignal(UserInputService.JumpRequest) end)
    end

    local function virtualInput()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new(1, 1))
        end)
    end

    function M.triggerAntiAFK()
        afkState.enabled = true
        M.bypassGameAFK()
        M.applyGameSpecificAFK()
        virtualInput()
        replayInput()
        disableIdledConnections()
    end

    function M.startAntiAFK(interval)
        interval = tonumber(interval) or 30
        afkState.enabled = true
        M.bypassGameAFK()
        M.applyGameSpecificAFK()

        if not afkState.idledConn then
            pcall(function()
                afkState.idledConn = LocalPlayer.Idled:Connect(function()
                    if afkState.enabled then M.triggerAntiAFK() end
                end)
            end)
        end

        if not afkState.running then
            afkState.running = true
            afkState.thread = task.spawn(function()
                while afkState.running and afkState.enabled do
                    M.triggerAntiAFK()
                    task.wait(interval)
                end
                afkState.running = false
            end)
        end
    end

    function M.stopAntiAFK()
        afkState.enabled = false
        afkState.running = false
        pcall(function()
            if afkState.idledConn then
                afkState.idledConn:Disconnect()
                afkState.idledConn = nil
            end
        end)
    end

    function M.setupAutoReconnect()
        pcall(function()
            local GuiService = game:GetService("GuiService")
            local TeleportService = game:GetService("TeleportService")
            if not Connections.AutoReconnect then
                Connections.AutoReconnect = GuiService.ErrorMessageChanged:Connect(function()
                    task.wait(1.5)
                    while true do
                        pcall(function()
                            TeleportService:Teleport(game.PlaceId, LocalPlayer)
                        end)
                        task.wait(5)
                    end
                end)
            end
        end)
    end

    return M
end)()

--------------------------------------------------------------------------------
-- CONTEXT OBJECT (returned to game logic)
--------------------------------------------------------------------------------
local ctx = {}

ctx.GAME_CONFIG = GAME_CONFIG
ctx.Config = Config
ctx.Stats = Stats
ctx.Flags = Flags
ctx.Connections = Connections
ctx.UIElements = UIElements

ctx.Window = Window
ctx.WindUI = WindUI
ctx.Protection = Protection

ctx.Players = Players
ctx.ReplicatedStorage = ReplicatedStorage
ctx.RunService = RunService
ctx.UserInputService = UserInputService
ctx.CoreGui = CoreGui
ctx.VirtualUser = VirtualUser
ctx.HttpService = HttpService
ctx.Lighting = Lighting
ctx.LocalPlayer = LocalPlayer

ctx.sendWebhook = sendWebhook
ctx.buildEmbed = buildEmbed
ctx.safeFireServer = safeFireServer
ctx.copyToClipboard = copyToClipboard
ctx.getHttpRequest = getHttpRequest
ctx.setUIElementVisual = setUIElementVisual
ctx.invokeUIElementCallback = invokeUIElementCallback
ctx.safeUpdateDropdown = safeUpdateDropdown

ctx.alive = function()
    return getgenv()[GAME_CONFIG.GlobalFlag]
end

--------------------------------------------------------------------------------
-- FPS BOOST HOOK  (logic belongs in the GAME MODULE, not here)
--------------------------------------------------------------------------------
-- The template only draws the two toggles in the "Settings" tab (bottom of the
-- tab list) and stores their state in Config.BoostUltra / Config.BoostNoEffects.
-- The actual boost work must be supplied by the game module by assigning these
-- two functions -- exactly like BoostFns in BreakSteal.lua / RooxHub.lua:
--
--   local BoostFns = (function()
--       ... your implementation ...
--       return {
--           Ultra     = function(enable) end,  -- kualitas render + shadow/atmosphere/terrain + strip partikel
--           NoEffects = function(enable) end,  -- matikan loop visual-only game (controller/VFX per-frame)
--       }
--   end)()
--   ctx.boost.Ultra     = BoostFns.Ultra
--   ctx.boost.NoEffects = BoostFns.NoEffects
--
-- The template calls ctx.boost.Ultra(state) / ctx.boost.NoEffects(state) from the
-- toggles and their saved value is re-applied on config load, so keep them
-- reversible and safe to call with false.
--------------------------------------------------------------------------------
ctx.boost = {
    Ultra = function(enable) end,
    NoEffects = function(enable) end,
}

--------------------------------------------------------------------------------
-- REGISTER GAME & START
--------------------------------------------------------------------------------
local statsParagraph = nil

function ctx:registerGame(callbacks)
    _gameCallbacks = callbacks or {}

    if _gameCallbacks.configFields then
        for k, v in pairs(_gameCallbacks.configFields) do
            Config[k] = v
        end
    end

    if _gameCallbacks.statsFields then
        for k, v in pairs(_gameCallbacks.statsFields) do
            Stats[k] = v
        end
    end

    if _gameCallbacks.flagFields then
        for k, v in pairs(_gameCallbacks.flagFields) do
            Flags[k] = v
        end
    end

    if _gameCallbacks.onInit then
        _gameCallbacks.onInit(ctx)
    end
end

function ctx:start()
    local TabOverview = Window:Tab({ Title = "Overview", Icon = "user" })
    TabOverview:Section({ Title = "User Profile", Icon = "user" })
    TabOverview:Image({ Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(LocalPlayer.UserId) .. "&w=150&h=150", AspectRatio = "1:1", Radius = 16 })
    TabOverview:Paragraph({ Title = LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")", Desc = "User ID: " .. tostring(LocalPlayer.UserId) })

    TabOverview:Section({ Title = "Game & Server Status", Icon = "server" })
    local gameServerParagraph = TabOverview:Paragraph({
        Title = "Game: " .. GAME_CONFIG.Name,
        Desc = "Place ID: " .. tostring(game.PlaceId) .. "\nServer: " .. tostring(#Players:GetPlayers()) .. "/" .. tostring(Players.MaxPlayers) .. " Player",
    })

    statsParagraph = TabOverview:Paragraph({
        Title = "Session Stats",
        Desc = "No stats configured yet.",
    })

    local function updateServerCount()
        pcall(function()
            gameServerParagraph:SetDesc("Place ID: " .. tostring(game.PlaceId) .. "\nServer: " .. tostring(#Players:GetPlayers()) .. "/" .. tostring(Players.MaxPlayers) .. " Player")
        end)
    end
    Players.PlayerAdded:Connect(updateServerCount)
    Players.PlayerRemoving:Connect(updateServerCount)

    local function updateStats()
        if _gameCallbacks and _gameCallbacks.onUpdateStats then
            pcall(_gameCallbacks.onUpdateStats, statsParagraph)
        end
    end
    ctx.updateStats = updateStats

    -- Auto-refresh the Overview "Session Stats" paragraph once a second.
    -- The game module does NOT need its own loop; just fill onUpdateStats.
    task.spawn(function()
        while getgenv()[GAME_CONFIG.GlobalFlag] do
            updateStats()
            task.wait(1)
        end
    end)

    if _gameCallbacks and _gameCallbacks.onCreateTabs then
        _gameCallbacks.onCreateTabs(ctx)
    end

    local TabMisc = Window:Tab({ Title = "Misc", Icon = "shield" })

    TabMisc:Section({ Title = "Anti System Control", Icon = "shield" })

    UIElements.AntiAFK = TabMisc:Toggle({
        Title = "Anti AFK",
        Desc = "Prevent Roblox's 20-minute kick & bypass the game's AFK script",
        Value = true,
        Callback = function(state)
            Flags.AntiAFK = state
            if state then
                Protection.bypassGameAFK()
                Protection.setupAutoReconnect()
                pcall(function()
                    LocalPlayer.Idled:Connect(function()
                        if Flags.AntiAFK then
                            Protection.triggerAntiAFK()
                        end
                    end)
                end)
                task.spawn(function()
                    while Flags.AntiAFK and getgenv()[GAME_CONFIG.GlobalFlag] do
                        Protection.triggerAntiAFK()
                        task.wait(Config.AntiAFKInterval)
                    end
                end)
            end
        end,
    })

    TabMisc:Toggle({
        Title = "Auto Reconnect Server",
        Desc = "Automatically reconnect if the connection to the server drops",
        Value = true,
        Callback = function(state)
            if state then
                Protection.setupAutoReconnect()
            end
        end,
    })

    local TabWebhook = Window:Tab({ Title = "Webhook", Icon = "bell" })

    TabWebhook:Section({ Title = "Discord Webhook Notifier", Icon = "bell" })

    UIElements.WebhookEnabled = TabWebhook:Toggle({
        Title = "Enable Webhook",
        Desc = "Send a Discord notification when a notable event occurs",
        Value = Config.WebhookEnabled,
        Callback = function(state)
            Config.WebhookEnabled = state
        end,
    })

    UIElements.WebhookUrl = TabWebhook:Input({
        Title = "Webhook URL",
        Desc = "Paste your Discord Webhook channel URL here",
        Value = Config.WebhookUrl or "",
        Placeholder = "https://discord.com/api/webhooks/...",
        ClearTextOnFocus = false,
        Callback = function(text)
            Config.WebhookUrl = text
        end,
    })

    if _gameCallbacks and _gameCallbacks.onWebhookFilters then
        _gameCallbacks.onWebhookFilters(TabWebhook, ctx)
    end

    TabWebhook:Section({ Title = "Ping Settings (Optional)", Icon = "at-sign" })

    UIElements.WebhookPing = TabWebhook:Toggle({
        Title = "Enable Mention / Ping",
        Desc = "Mention your Discord account when a webhook is sent",
        Value = Config.WebhookPing,
        Callback = function(state)
            Config.WebhookPing = state
        end,
    })

    UIElements.WebhookUserId = TabWebhook:Input({
        Title = "Discord User ID",
        Desc = "Your Discord User ID to mention (example: 123456789012345678)",
        Value = Config.WebhookUserId or "",
        Placeholder = "Enter Discord User ID...",
        ClearTextOnFocus = false,
        Callback = function(text)
            Config.WebhookUserId = text
        end,
    })

    TabWebhook:Section({ Title = "Test Webhook", Icon = "send" })

    TabWebhook:Button({
        Title = "Send Test Webhook",
        Desc = "Test sending a Discord embed with simulated data",
        Callback = function()
            task.spawn(function()
                WindUI:Notify({
                    Title = "RooxHub • Webhook",
                    Content = "Sending test webhook to Discord...",
                    Duration = 2,
                })

                local okSend, statusMsg = sendTestWebhook()

                if okSend then
                    WindUI:Notify({
                        Title = "RooxHub • Webhook",
                        Content = "Test webhook successfully sent to Discord!",
                        Duration = 3.5,
                    })
                else
                    WindUI:Notify({
                        Title = "RooxHub • Webhook",
                        Content = tostring(statusMsg or "Failed to send webhook."),
                        Duration = 5,
                    })
                end
            end)
        end,
    })

    local TabConfig = Window:Tab({ Title = "Configs", Icon = "folder-cog" })

    local currentConfigNameInput = "default"
    local selectedConfigInDropdown = "default"
    local jsonInputText = ""

    TabConfig:Section({ Title = "Profile Management", Icon = "file-text" })

    TabConfig:Input({
        Title = "Config Name",
        Desc = "Config profile file name",
        Value = "default",
        Placeholder = "Example: my_config",
        ClearTextOnFocus = false,
        Callback = function(text)
            currentConfigNameInput = text
        end,
    })

    local ConfigDropdown = TabConfig:Dropdown({
        Title = "Select Saved Config",
        Desc = "List of config files available in storage",
        Values = getSavedConfigsList(),
        Value = SystemSettings.LastConfigName or "default",
        Callback = function(val)
            selectedConfigInDropdown = val
        end,
    })

    TabConfig:Button({
        Title = "Save Config",
        Desc = "Save all current settings, farming toggles & filters",
        Callback = function()
            local success, savedName = saveConfigFile(currentConfigNameInput)
            if success then
                safeUpdateDropdown(ConfigDropdown, getSavedConfigsList())
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Config '" .. savedName .. "' saved successfully!",
                    Duration = 2.5,
                })
            else
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Failed to save config to the storage folder.",
                    Duration = 2.5,
                })
            end
        end,
    })

    TabConfig:Button({
        Title = "Load Selected Config",
        Desc = "Apply the config profile selected from the list",
        Callback = function()
            local target = selectedConfigInDropdown or currentConfigNameInput
            local success = loadConfigFile(target)
            if success then
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Config '" .. target .. "' applied successfully!",
                    Duration = 2.5,
                })
            else
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Config file '" .. tostring(target) .. "' not found.",
                    Duration = 2.5,
                })
            end
        end,
    })

    TabConfig:Button({
        Title = "Refresh Config List",
        Desc = "Reload the list of saved config files",
        Callback = function()
            local list = getSavedConfigsList()
            safeUpdateDropdown(ConfigDropdown, list)
            WindUI:Notify({
                Title = "RooxHub • Configs",
                Content = "Config list refreshed! (" .. tostring(#list) .. " file(s))",
                Duration = 2,
            })
        end,
    })

    TabConfig:Button({
        Title = "Delete Config",
        Desc = "Permanently delete the selected config file",
        Callback = function()
            local target = selectedConfigInDropdown
            local success = deleteConfigFile(target)
            if success then
                local list = getSavedConfigsList()
                safeUpdateDropdown(ConfigDropdown, list)
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Config '" .. tostring(target) .. "' deleted successfully.",
                    Duration = 2.5,
                })
            else
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Failed to delete config '" .. tostring(target) .. "'.",
                    Duration = 2.5,
                })
            end
        end,
    })

    TabConfig:Section({ Title = "Auto Execute Config", Icon = "play-circle" })

    UIElements.AutoExecuteConfig = TabConfig:Toggle({
        Title = "Auto Execute Last Config",
        Desc = "Otomatis load dan jalankan config terakhir saat script dijalankan dari loader atau rejoin server",
        Value = SystemSettings.AutoExecuteConfig,
        Callback = function(state)
            SystemSettings.AutoExecuteConfig = state
            saveSystemSettings()
            WindUI:Notify({
                Title = "RooxHub • Configs",
                Content = state and "Auto Execute Config: ON" or "Auto Execute Config: OFF",
                Duration = 2,
            })
        end,
    })

    TabConfig:Section({ Title = "JSON Share & Import", Icon = "share-2" })

    TabConfig:Button({
        Title = "Copy Config JSON (Clipboard)",
        Desc = "Copy the entire current configuration as JSON text",
        Callback = function()
            local data = exportConfigTable()
            local ok, json = pcall(function()
                return HttpService:JSONEncode(data)
            end)
            if ok and json then
                copyToClipboard(json)
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Config JSON copied to clipboard!",
                    Duration = 3,
                })
            end
        end,
    })

    TabConfig:Input({
        Title = "Paste Config JSON",
        Desc = "Paste configuration JSON text from another player",
        Value = "",
        Placeholder = 'Paste JSON code here...',
        ClearTextOnFocus = true,
        Callback = function(text)
            jsonInputText = text
        end,
    })

    TabConfig:Button({
        Title = "Import & Apply JSON",
        Desc = "Apply the configuration from the pasted JSON text",
        Callback = function()
            if not jsonInputText or jsonInputText == "" then
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "JSON text is still empty!",
                    Duration = 2,
                })
                return
            end
            local ok, data = pcall(function()
                return HttpService:JSONDecode(jsonInputText)
            end)
            if ok and typeof(data) == "table" then
                if data._gameId and data._gameId ~= GAME_CONFIG.Folder then
                    WindUI:Notify({
                        Title = "RooxHub • Configs",
                        Content = "JSON ditolak! Config ini milik game '" .. tostring(data._gameName or data._gameId) .. "', bukan untuk " .. GAME_CONFIG.Name .. ".",
                        Duration = 5,
                    })
                    return
                end
                local applied = applyConfig(data)
                if applied then
                    WindUI:Notify({
                        Title = "RooxHub • Configs",
                        Content = "JSON configuration applied successfully!",
                        Duration = 3,
                    })
                else
                    WindUI:Notify({
                        Title = "RooxHub • Configs",
                        Content = "Invalid JSON data format.",
                        Duration = 2.5,
                    })
                end
            else
                WindUI:Notify({
                    Title = "RooxHub • Configs",
                    Content = "Failed to process JSON code.",
                    Duration = 2.5,
                })
            end
        end,
    })

    --------------------------------------------------------------------------
    -- TAB: SETTINGS (bottom of the tab list)
    -- FPS Boost: only 2 toggles -- "Ultra FPS Boost" and "No Effects".
    -- The actual boost LOGIC lives in the GAME MODULE (see the "FPS BOOST HOOK"
    -- comment near ctx.boost). These callbacks only persist the state and call it.
    --------------------------------------------------------------------------
    local TabSettings = Window:Tab({ Title = "Settings", Icon = "settings" })

    TabSettings:Section({ Title = "Performance & FPS Boost", Icon = "zap" })

    UIElements.BoostUltra = TabSettings:Toggle({
        Title = "Ultra FPS Boost",
        Desc = "Lower render quality, kill shadow/atmosphere/terrain and strip textures/particles. Biggest boost.",
        Value = Config.BoostUltra,
        Callback = function(state)
            Config.BoostUltra = state and true or false
            pcall(ctx.boost.Ultra, Config.BoostUltra)
        end,
    })

    UIElements.BoostNoEffects = TabSettings:Toggle({
        Title = "No Effects",
        Desc = "Stop the game's visual-only effect/particle/VFX loops so they never run each frame.",
        Value = Config.BoostNoEffects,
        Callback = function(state)
            Config.BoostNoEffects = state and true or false
            pcall(ctx.boost.NoEffects, Config.BoostNoEffects)
        end,
    })

    -- Re-apply the saved boost state once, after the UI is up (staggered, safe).
    task.defer(function()
        if Config.BoostUltra then pcall(ctx.boost.Ultra, true) end
        task.wait(0.5)
        if Config.BoostNoEffects then pcall(ctx.boost.NoEffects, true) end
    end)

    --------------------------------------------------------------------------
    -- CLEANUP / EXIT SYSTEM
    --------------------------------------------------------------------------
    local isCleanedUp = false
    local function stopScript()
        if isCleanedUp then return end
        isCleanedUp = true

        getgenv()[GAME_CONFIG.GlobalFlag] = false
        getgenv()[GAME_CONFIG.CleanupFlag] = nil

        if Connections.AntiRender then
            pcall(function() Connections.AntiRender:Disconnect() end)
            Connections.AntiRender = nil
        end

        if Config.BoostUltra then pcall(ctx.boost.Ultra, false) end
        if Config.BoostNoEffects then pcall(ctx.boost.NoEffects, false) end
        if _gameCallbacks and _gameCallbacks.onCleanup then
            pcall(_gameCallbacks.onCleanup)
        end

        for k in pairs(Flags) do Flags[k] = false end

        for _, conn in pairs(Connections) do
            pcall(function()
                if typeof(conn) == "RBXScriptConnection" then
                    conn:Disconnect()
                elseif type(conn) == "table" and conn.Disconnect then
                    conn:Disconnect()
                end
            end)
        end
        for k in pairs(Connections) do
            Connections[k] = nil
        end

        pcall(function()
            if Window and not Window.Destroyed then
                Window.Destroyed = true
                task.spawn(function()
                    pcall(function() Window:Destroy() end)
                end)
            end
        end)

        task.delay(0.1, function()
            pcall(function()
                if rootGui and rootGui.Parent then
                    rootGui:Destroy()
                end
            end)
        end)

        print("[RooxHub] " .. GAME_CONFIG.Name .. " has been fully stopped.")
    end

    getgenv()[GAME_CONFIG.CleanupFlag] = stopScript

    pcall(function()
        Window:OnDestroy(stopScript)
    end)

    --------------------------------------------------------------------------
    -- STARTUP
    --------------------------------------------------------------------------
    pcall(function() TabOverview:Select() end)

    task.spawn(function()
        local timeout = os.clock() + 10
        while os.clock() < timeout do
            if Window and Window.UIElements and Window.UIElements.Main then
                break
            end
            task.wait(0.2)
        end
        task.wait(0.5)

        loadSystemSettings()
        if SystemSettings.AutoExecuteConfig then
            local target = SystemSettings.LastConfigName or "default"
            local success = loadConfigFile(target)
            if success then
                WindUI:Notify({
                    Title = "RooxHub • Auto Config",
                    Content = "Config '" .. tostring(target) .. "' auto-loaded successfully!",
                    Duration = 3,
                })
            end
        end
    end)

    task.delay(0.5, fixSidebarLayout)
    task.delay(1.0, fixSidebarLayout)
    task.delay(2.0, fixSidebarLayout)

    WindUI:Notify({ Title = "RooxHub Loaded Successfully", Content = GAME_CONFIG.Name .. " " .. GAME_CONFIG.Version .. " is ready to use!", Duration = 4 })

    return ctx
end

return ctx
end
