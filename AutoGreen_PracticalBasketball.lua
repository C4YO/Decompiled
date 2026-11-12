--[[
	Auto Green — Practical Basketball (place 106120159518740)

	Como funciona (baseado no decompile):
	- O servidor replica os atributos "meterOffset" / "meterRotation" no HumanoidRootPart
	  enquanto o medidor de arremesso enche (Controllers/Meter só renderiza).
	- A janela verde é desenhada no Meter_Green via UIGradient.Transparency
	  (fração da janela = clamp(1 - pct/100)).
	- Soltar a tecla de arremesso dispara InputService.Shoot:Fire({ Shoot = false }),
	  que encerra o medidor e envia o timing ao servidor.

	O script monitora o meterOffset, estima a velocidade do medidor, solta a tecla
	na borda da janela verde (compensando o ping).

	Toggle: RightControl | Fechar: não precisa (script local)
	Uso: segure o arremesso normalmente; o script solta sozinho dentro da janela.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Stats = game:GetService("Stats")

local LocalPlayer = Players.LocalPlayer

local Config = {
	Enabled = true,

	ToggleKey = Enum.KeyCode.RightControl,

	ShootKey = Enum.KeyCode.E,
	AltKeys = { Enum.KeyCode.E, Enum.KeyCode.Space },

	TargetOffset = 0,
	HalfWindow = 0.05,
	AutoWindow = true,
	MinHalfWindow = 0.02,

	PingLead = true,
	MaxLead = 0.15,
	ExtraLead = 0,

	Debug = false,
}

local VIM
pcall(function()
	VIM = game:GetService("VirtualInputManager")
end)

local released = false
local samples = {}
local lastKeyDown = Config.ShootKey
local lastKeyDownTime = 0

local function getPing()
	local ok, ping = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and type(ping) == "number" then
		return ping / 1000
	end
	return 0
end

local function findMeter(character)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	for _, container in ipairs({ hrp, head }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child.Name:match("Meter$") and child:FindFirstChild("Meter_Green", true) then
					return child
				end
			end
		end
	end
	return nil
end

local function getGreenWidth(meter)
	local green = meter and meter:FindFirstChild("Meter_Green", true)
	local gradient = green and green:FindFirstChildOfClass("UIGradient")
	if not gradient then
		return nil
	end
	local keypoints = gradient.Transparency.Keypoints
	local start
	for i, kp in ipairs(keypoints) do
		if kp.Value < 1 then
			start = kp.Time
			for j = i + 1, #keypoints do
				if keypoints[j].Value >= 1 then
					return math.abs(keypoints[j].Time - start)
				end
			end
			break
		end
	end
	return nil
end

local function releaseShot()
	local key = lastKeyDown
	if os.clock() - lastKeyDownTime > 2 then
		key = Config.ShootKey
	end
	if VIM then
		VIM:SendKeyEvent(false, key, false, game)
		if Config.Debug then
			print("[AutoGreen] release:", key.Name)
		end
	else
		warn("[AutoGreen] VirtualInputManager indisponível neste ambiente")
	end
end

local function getVelocity(now)
	local cutoff = now - 0.15
	while #samples > 0 and samples[1][1] < cutoff do
		table.remove(samples, 1)
	end
	if #samples < 2 then
		return 0
	end
	local oldest = samples[1]
	local newest = samples[#samples]
	local dt = newest[1] - oldest[1]
	if dt <= 0 then
		return 0
	end
	return (newest[2] - oldest[2]) / dt
end

local function step()
	local character = LocalPlayer.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and hrp) then
		released = false
		samples = {}
		return
	end

	if character:GetAttribute("Action") ~= "Shooting" then
		released = false
		samples = {}
		return
	end

	local offset = hrp:GetAttribute("meterOffset")
	if offset == nil then
		return
	end

	local now = os.clock()
	table.insert(samples, { now, offset })
	local velocity = getVelocity(now)

	if released then
		return
	end

	local halfWindow = Config.HalfWindow
	if Config.AutoWindow then
		local width = getGreenWidth(findMeter(character))
		if width then
			halfWindow = math.max(width / 2, Config.MinHalfWindow)
		end
	end

	local distance = offset - Config.TargetOffset
	local lead = 0
	if Config.PingLead then
		lead = math.min(getPing() / 2 + Config.ExtraLead, Config.MaxLead)
	end

	local approaching = (distance < 0 and velocity > 0) or (distance > 0 and velocity < 0)
	local timeToTarget = approaching and math.abs(distance) / math.max(math.abs(velocity), 1e-6) or math.huge

	if math.abs(distance) <= halfWindow or timeToTarget <= lead then
		released = true
		if Config.Debug then
			print(string.format(
				"[AutoGreen] offset=%.4f vel=%.4f janela=±%.4f lead=%.3fs",
				offset, velocity, halfWindow, lead
			))
		end
		releaseShot()
	end
end

local gui
local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "AutoGreenStatus"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 12, 1, -12)
	label.Size = UDim2.fromOffset(170, 28)
	label.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	label.BackgroundTransparency = 0.35
	label.TextColor3 = Color3.fromRGB(85, 255, 127)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = "AUTO GREEN: ON"
	label.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label

	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local function setStatus(on)
	Config.Enabled = on
	if gui then
		local label = gui:FindFirstChild("Status")
		if label then
			label.Text = "AUTO GREEN: " .. (on and "ON" or "OFF")
			label.TextColor3 = on and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 82, 82)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if table.find(Config.AltKeys, input.KeyCode) then
		lastKeyDown = input.KeyCode
		lastKeyDownTime = os.clock()
	end
	if input.KeyCode == Config.ToggleKey then
		setStatus(not Config.Enabled)
	end
end)

buildGui()

RunService.Heartbeat:Connect(function()
	if Config.Enabled then
		step()
	end
end)

print("[AutoGreen] carregado — RightControl liga/desliga")
