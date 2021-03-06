local E, L, V, P, G = unpack(select(2, ...)); --Import: Engine, Locales, PrivateDB, ProfileDB, GlobalDB
local DT = E:GetModule('DataTexts')
local TT = E:GetModule('Tooltip')
local LDB = E.Libs.LDB
local LSM = E.Libs.LSM

local _G = _G
local tostring = tostring
local tinsert, wipe, sort, type, error, pcall = tinsert, wipe, sort, type, error, pcall
local ipairs, pairs, next, strlen, strfind = ipairs, pairs, next, strlen, strfind
local CloseDropDownMenus = CloseDropDownMenus
local CreateFrame = CreateFrame
local EasyMenu = EasyMenu
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local MouseIsOver = MouseIsOver
local RegisterStateDriver = RegisterStateDriver
local UIDropDownMenu_SetAnchor = UIDropDownMenu_SetAnchor
local UnregisterStateDriver = UnregisterStateDriver
local MISCELLANEOUS = MISCELLANEOUS

local ActivateHyperMode
local HyperList = {}

DT.SelectedDatatext = nil
DT.HyperList = HyperList
DT.RegisteredPanels = {}
DT.RegisteredDataTexts = {}
DT.LoadedInfo = {}
DT.PanelPool = {
	InUse = {},
	Free = {},
	Count = 0
}
DT.UnitEvents = {
	UNIT_AURA = true,
	UNIT_RESISTANCES = true,
	UNIT_STATS = true,
	UNIT_ATTACK_POWER = true,
	UNIT_RANGED_ATTACK_POWER = true,
	UNIT_TARGET = true,
	UNIT_SPELL_HASTE = true
}

function DT:SetEasyMenuAnchor(menu, dt)
	local point = E:GetScreenQuadrant(dt)
	local bottom = point and strfind(point, 'BOTTOM')
	local left = point and strfind(point, 'LEFT')

	local anchor1 = (bottom and left and 'BOTTOMLEFT') or (bottom and 'BOTTOMRIGHT') or (left and 'TOPLEFT') or 'TOPRIGHT'
	local anchor2 = (bottom and left and 'TOPLEFT') or (bottom and 'TOPRIGHT') or (left and 'BOTTOMLEFT') or 'BOTTOMRIGHT'

	UIDropDownMenu_SetAnchor(menu, 0, 0, anchor1, dt, anchor2)
end

--> [HyperDT Credits] <--
--> Original Work: NihilisticPandemonium
--> Modified by Azilroka! :)

function DT:SingleHyperMode(_, key, active)
	if DT.SelectedDatatext and (key == 'LALT' or key == 'RALT') then
		if active == 1 and MouseIsOver(DT.SelectedDatatext) then
			DT:OnLeave()
			DT:SetEasyMenuAnchor(DT.EasyMenu, DT.SelectedDatatext)
			EasyMenu(HyperList, DT.EasyMenu, nil, nil, nil, 'MENU')
		elseif _G.DropDownList1:IsShown() and not _G.DropDownList1:IsMouseOver() then
			CloseDropDownMenus()
		end
	end
end

function DT:HyperClick()
	DT.SelectedDatatext = self
	DT:SetEasyMenuAnchor(DT.EasyMenu, DT.SelectedDatatext)
	EasyMenu(HyperList, DT.EasyMenu, nil, nil, nil, 'MENU')
end

function DT:EnableHyperMode(Panel)
	DT:OnLeave()

	if Panel then
		for _, dt in pairs(Panel.dataPanels) do
			dt.overlay:Show()
			dt:SetScript('OnEnter', nil)
			dt:SetScript('OnLeave', nil)
			dt:SetScript('OnClick', DT.HyperClick)
		end
	else
		for _, panel in pairs(DT.RegisteredPanels) do
			for _, dt in pairs(panel.dataPanels) do
				dt.overlay:Show()
				dt:SetScript('OnEnter', nil)
				dt:SetScript('OnLeave', nil)
				dt:SetScript('OnClick', DT.HyperClick)
			end
		end
	end
end

function DT:OnEnter()
	if E.db.datatexts.noCombatHover and InCombatLockdown() then return end

	if self.parent then
		DT.SelectedDatatext = self
	end

	if self.MouseEnters then
		for _, func in ipairs(self.MouseEnters) do
			func(self)
		end
	end

	DT.MouseEnter(self)
end

function DT:OnLeave()
	if E.db.datatexts.noCombatHover and InCombatLockdown() then return end

	if self.MouseLeaves then
		for _, func in ipairs(self.MouseLeaves) do
			func(self)
		end
	end

	DT.MouseLeave(self)
	DT.tooltip:Hide()
end

function DT:MouseEnter()
	local frame = self.parent or self
	if frame.db and frame.db.mouseover then
		E:UIFrameFadeIn(frame, 0.2, frame:GetAlpha(), 1)
	end
end

function DT:MouseLeave()
	local frame = self.parent or self
	if frame.db and frame.db.mouseover then
		E:UIFrameFadeOut(frame, 0.2, frame:GetAlpha(), 0)
	end
end

function DT:FetchFrame(givenName)
	local panelExists = DT.PanelPool.InUse[givenName]
	if panelExists then return panelExists end

	local count = DT.PanelPool.Count
	local name = 'ElvUI_DTPanel' .. count
	local frame

	local poolName, poolFrame = next(DT.PanelPool.Free)
	if poolName then
		frame = poolFrame
		DT.PanelPool.Free[poolName] = nil
	else
		frame = CreateFrame('Frame', name, E.UIParent)
		DT.PanelPool.Count = DT.PanelPool.Count + 1
	end

	DT.PanelPool.InUse[givenName] = frame

	return frame
end

function DT:EmptyPanel(panel)
	panel:Hide()

	for _, dt in ipairs(panel.dataPanels) do
		dt:UnregisterAllEvents()
		dt:SetScript('OnUpdate', nil)
		dt:SetScript('OnEvent', nil)
		dt:SetScript('OnEnter', nil)
		dt:SetScript('OnLeave', nil)
		dt:SetScript('OnClick', nil)

		if dt.text:GetText() then
			dt.text:SetText(' ') -- Keep this as a space, it fixes init load in with a custom font added by a plugin. ~Simpy
		end
	end

	UnregisterStateDriver(panel, 'visibility')
	E:DisableMover(panel.moverName)
end

function DT:ReleasePanel(givenName)
	local panel = DT.PanelPool.InUse[givenName]
	if panel then
		DT:EmptyPanel(panel)
		DT.PanelPool.Free[givenName] = panel
		DT.PanelPool.InUse[givenName] = nil
		DT.RegisteredPanels[givenName] = nil
		E.db.movers[panel.moverName] = nil
	end
end

function DT:BuildPanelFrame(name, db, initLoad)
	db = db or E.global.datatexts.customPanels[name] or DT:Panel_DefaultGlobalSettings(name)

	local Panel = DT:FetchFrame(name)
	Panel:ClearAllPoints()
	Panel:Point('CENTER')
	Panel:Size(db.width, db.height)

	local MoverName = 'DTPanel'..name..'Mover'
	Panel.moverName = MoverName
	Panel.givenName = name

	local holder = E:GetMoverHolder(MoverName)
	if holder then
		E:SetMoverPoints(MoverName, Panel)
	else
		E:CreateMover(Panel, MoverName, name, nil, nil, nil, nil, nil, 'general,solo')
	end

	DT:RegisterPanel(Panel, db.numPoints, db.tooltipAnchor, db.tooltipXOffset, db.tooltipYOffset, db.growth == 'VERTICAL')

	if not initLoad then
		DT:UpdatePanelAttributes(name, db)
	end
end

local LDBHex = '|cffFFFFFF'
function DT:BuildPanelFunctions(name, obj)
	local panel

	local function OnEnter(dt)
		DT:SetupTooltip(dt)
		if obj.OnTooltipShow then obj.OnTooltipShow(DT.tooltip) end
		if obj.OnEnter then obj.OnEnter(dt) end
		DT.tooltip:Show()
	end

	local function OnLeave(dt)
		if obj.OnLeave then obj.OnLeave(dt) end
		DT.tooltip:Hide()
	end

	local function OnClick(dt, button)
		if obj.OnClick then obj.OnClick(dt, button) end
	end

	local function UpdateText(_, Name, _, Value)
		if Value == nil or (strlen(Value) >= 3) or Value == 'n/a' or Name == Value then
			panel.text:SetText(Value ~= 'n/a' and Value or Name)
		else
			panel.text:SetFormattedText('%s: %s%s|r', Name, LDBHex, Value)
		end
	end

	local function OnCallback(newHex)
		if name and obj then
			LDBHex = newHex
			LDB.callbacks:Fire('LibDataBroker_AttributeChanged_'..name..'_text', name, nil, obj.text, obj)
		end
	end

	local function OnEvent(dt)
		panel = dt
		LDB:RegisterCallback('LibDataBroker_AttributeChanged_'..name..'_text', UpdateText)
		LDB:RegisterCallback('LibDataBroker_AttributeChanged_'..name..'_value', UpdateText)
		OnCallback(LDBHex)
	end

	return OnEnter, OnLeave, OnClick, OnCallback, OnEvent, UpdateText
end

function DT:SetupObjectLDB(name, obj)
	local onEnter, onLeave, onClick, onCallback, onEvent = DT:BuildPanelFunctions(name, obj)
	local data = DT:RegisterDatatext(name, 'Data Broker', nil, onEvent, nil, onClick, onEnter, onLeave)
	E.valueColorUpdateFuncs[onCallback] = true
	data.isLibDataBroker = true

	-- Update config if it has been loaded
	if DT.PanelLayoutOptions then
		DT:PanelLayoutOptions()
	end
end

function DT:RegisterLDB()
	for name, obj in LDB:DataObjectIterator() do
		DT:SetupObjectLDB(name, obj)
	end
end

function DT:GetDataPanelPoint(panel, i, numPoints, vertical)
	if numPoints == 1 then
		return 'CENTER', panel, 'CENTER'
	else
		local point, relativePoint, xOffset, yOffset = 'LEFT', i == 1 and 'LEFT' or 'RIGHT', 4, 0
		if vertical then
			point, relativePoint, xOffset, yOffset = 'TOP', i == 1 and 'TOP' or 'BOTTOM', 0, -4
		end

		local lastPanel = (i == 1 and panel) or panel.dataPanels[i - 1]
		return point, lastPanel, relativePoint, xOffset, yOffset
	end
end

function DT:SetupTooltip(panel)
	local parent = panel:GetParent()
	DT.tooltip:Hide()
	DT.tooltip:SetOwner(panel, parent.anchor, parent.xOff, parent.yOff)
	DT.tooltip:ClearLines()

	if not _G.GameTooltip:IsForbidden() then
		_G.GameTooltip:Hide() -- WHY??? BECAUSE FUCK GAMETOOLTIP, THATS WHY!!
	end
end

function DT:RegisterPanel(panel, numPoints, anchor, xOff, yOff, vertical)
	local realName = panel:GetName()
	local name = panel.givenName or realName

	if not name then
		E:Print('DataTexts: Requires a panel name.')
		return
	end

	DT.RegisteredPanels[name] = panel

	panel:SetScript('OnEnter', DT.OnEnter)
	panel:SetScript('OnLeave', DT.OnLeave)
	panel:SetScript('OnSizeChanged', DT.PanelSizeChanged)

	panel.dataPanels = panel.dataPanels or {}
	panel.numPoints = numPoints
	panel.xOff = xOff
	panel.yOff = yOff
	panel.anchor = anchor
	panel.vertical = vertical
end

function DT:Panel_DefaultGlobalSettings(name)
	local db = E:CopyTable({}, G.datatexts.newPanelInfo)
	db.enable = nil
	db.name = nil

	E.global.datatexts.customPanels[name] = db

	return db
end

function DT:AssignPanelToDataText(dt, data, event, ...)
	dt.name = data.name or '' -- This is needed for Custom Currencies

	if data.events then
		for _, ev in pairs(data.events) do
			if data.eventFunc then
				if data.objectEvent then
					if not dt.objectEventFunc then
						dt.objectEvent = data.objectEvent
						dt.objectEventFunc = function(_, ...)
							if data.eventFunc then data.eventFunc(dt, ...) end
						end
					end
					if not E:HasFunctionForObject(ev, data.objectEvent, dt.objectEventFunc) then
						E:RegisterEventForObject(ev, data.objectEvent, dt.objectEventFunc)
					end
				elseif DT.UnitEvents[ev] then
					pcall(dt.RegisterUnitEvent, dt, ev, 'player')
				else
					pcall(dt.RegisterEvent, dt, ev)
				end
			end
		end
	end

	local ev = event or 'ELVUI_FORCE_UPDATE'
	if data.eventFunc then
		if not data.objectEvent then
			dt:SetScript('OnEvent', data.eventFunc)
		end

		data.eventFunc(dt, ev, ...)
	end

	if data.onUpdate then
		dt:SetScript('OnUpdate', data.onUpdate)
		data.onUpdate(dt, 20000)
	end

	if data.onClick then
		dt:SetScript('OnClick', function(p, button)
			if E.db.datatexts.noCombatClick and InCombatLockdown() then return end
			data.onClick(p, button)
		end)
	end

	if data.onEnter then
		tinsert(dt.MouseEnters, data.onEnter)
	end
	if data.onLeave then
		tinsert(dt.MouseLeaves, data.onLeave)
	end
end

function DT:GetTextAttributes(panel, db)
	local panelWidth, panelHeight = panel:GetSize()
	local numPoints = db and db.numPoints or panel.numPoints or 1
	local vertical = db and db.vertical or panel.vertical

	local width, height = (panelWidth / numPoints) - 4, panelHeight - 4
	if vertical then width, height = panelWidth - 4, (panelHeight / numPoints) - 4 end

	return width, height, vertical, numPoints
end

function DT:UpdatePanelInfo(panelName, panel, ...)
	if not panel then panel = DT.RegisteredPanels[panelName] end
	local db = panel.db or P.datatexts.panels[panelName] and DT.db.panels[panelName]
	if not db then return end

	local info = DT.LoadedInfo
	local font, fontSize, fontOutline = info.font, info.fontSize, info.fontOutline
	if db and db.fonts and db.fonts.enable then
		font, fontSize, fontOutline = LSM:Fetch('font', db.fonts.font), db.fonts.fontSize, db.fonts.fontOutline
	end

	local chatPanel = panelName == 'LeftChatDataPanel' or panelName == 'RightChatDataPanel'
	local battlePanel = info.isInBattle and chatPanel and (not DT.ForceHideBGStats and E.db.datatexts.battleground)
	if battlePanel then
		DT:RegisterEvent('UPDATE_BATTLEFIELD_SCORE')
		DT.ShowingBattleStats = info.instanceType
	elseif chatPanel and DT.ShowingBattleStats then
		DT:UnregisterEvent('UPDATE_BATTLEFIELD_SCORE')
		DT.ShowingBattleStats = nil
	end

	local width, height, vertical, numPoints = DT:GetTextAttributes(panel, db)

	for i = 1, numPoints do
		local dt = panel.dataPanels[i]
		if not dt then
			dt = CreateFrame('Button', panelName..'_DataText'..i, panel)
			dt.MouseEnters = {}
			dt.MouseLeaves = {}
			dt:RegisterForClicks('AnyUp')

			local text = dt:CreateFontString(nil, 'ARTWORK')
			text:SetAllPoints()
			text:SetJustifyH('CENTER')
			text:SetJustifyV('MIDDLE')
			dt.text = text

			local overlay = dt:CreateTexture(nil, 'OVERLAY')
			overlay:SetTexture(E.media.blankTex)
			overlay:SetVertexColor(0.3, 0.9, 0.3, .3)
			overlay:SetAllPoints()
			dt.overlay = overlay

			panel.dataPanels[i] = dt
		end
	end

	panel:SetTemplate(db.backdrop and (db.panelTransparency and 'Transparent' or 'Default') or 'NoBackdrop', true)
	E:TogglePixelBorders(panel, db.border)

	--Restore Panels
	for i, dt in ipairs(panel.dataPanels) do
		dt:SetShown(i <= numPoints)
		dt:Size(width, height)
		dt:ClearAllPoints()
		dt:Point(DT:GetDataPanelPoint(panel, i, numPoints, vertical))
		dt:UnregisterAllEvents()
		dt:SetScript('OnUpdate', nil)
		dt:SetScript('OnEvent', nil)
		dt:SetScript('OnClick', nil)
		dt:SetScript('OnEnter', DT.OnEnter)
		dt:SetScript('OnLeave', DT.OnLeave)
		wipe(dt.MouseEnters)
		wipe(dt.MouseLeaves)

		dt.overlay:Hide()
		dt.pointIndex = i
		dt.parent = panel
		dt.parentName = panelName
		dt.battleStats = battlePanel
		dt.db = db

		E:StopFlash(dt)

		if dt.objectEvent and dt.objectEventFunc then
			E:UnregisterAllEventsForObject(dt.objectEvent, dt.objectEventFunc)
			dt.objectEvent, dt.objectEventFunc = nil, nil
		end

		local text = dt.text
		text:FontTemplate(font, fontSize, fontOutline)
		text:SetWordWrap(DT.db.wordWrap)
		text:SetText(' ') -- Keep this as a space, it fixes init load in with a custom font added by a plugin. ~Simpy

		if battlePanel then
			dt:SetScript('OnClick', DT.ToggleBattleStats)
		else
			local assigned = DT.RegisteredDataTexts[ DT.db.panels[panelName][i] ]
			if assigned then DT:AssignPanelToDataText(dt, assigned, ...) end
		end
	end
end

function DT:LoadDataTexts(...)
	local data = DT.LoadedInfo
	data.font, data.fontSize, data.fontOutline = LSM:Fetch('font', DT.db.font), DT.db.fontSize, DT.db.fontOutline
	data.inInstance, data.instanceType = IsInInstance()
	data.isInBattle = data.inInstance and (data.instanceType == 'pvp' or data.instanceType == 'arena')

	for panel, db in pairs(E.global.datatexts.customPanels) do
		DT:UpdatePanelAttributes(panel, db)
	end

	for panelName, panel in pairs(DT.RegisteredPanels) do
		if not E.global.datatexts.customPanels[panelName] or DT.db.panels[panelName].enable then
			DT:UpdatePanelInfo(panelName, panel, ...)
		end
	end

	if DT.ShowingBattleStats then
		DT:UPDATE_BATTLEFIELD_SCORE()
	end
end

function DT:PanelSizeChanged()
	if not self.dataPanels then return end
	local db = self.db or P.datatexts.panels[self.name] and DT.db.panels[self.name]
	local width, height, vertical, numPoints = DT:GetTextAttributes(self, db)

	for i, dt in ipairs(self.dataPanels) do
		dt:Size(width, height)
		dt:ClearAllPoints()
		dt:Point(DT:GetDataPanelPoint(self, i, numPoints, vertical))
	end
end

function DT:UpdatePanelAttributes(name, db)
	local Panel = DT.PanelPool.InUse[name]
	DT.OnLeave(Panel)

	Panel.db = db
	Panel.name = name
	Panel.numPoints = db.numPoints
	Panel.xOff = db.tooltipXOffset
	Panel.yOff = db.tooltipYOffset
	Panel.anchor = db.tooltipAnchor
	Panel.vertical = db.growth == 'VERTICAL'
	Panel:Size(db.width, db.height)
	Panel:SetFrameStrata(db.frameStrata)
	Panel:SetFrameLevel(db.frameLevel)

	E:UIFrameFadeIn(Panel, 0.2, Panel:GetAlpha(), db.mouseover and 0 or 1)

	if not DT.db.panels[name] then
		DT.db.panels[name] = { enable = true }
	end

	for i = 1, E.global.datatexts.customPanels[name].numPoints do
		if not DT.db.panels[name][i] then
			DT.db.panels[name][i] = ''
		end
	end

	if DT.db.panels[name].enable then
		E:EnableMover(Panel.moverName)
		RegisterStateDriver(Panel, 'visibility', db.visibility)
		DT:UpdatePanelInfo(name, Panel)
	else
		DT:EmptyPanel(Panel)
	end
end

function DT:GetMenuListCategory(category)
	for i, info in ipairs(HyperList) do
		if info.text == category then
			return i
		end
	end
end

function DT:SortMenuList(list)
	for _, menu in pairs(list) do
		if menu.menuList then
			DT:SortMenuList(menu.menuList)
		end
	end

	sort(list, function(a, b) return a.text < b.text end)
end

function DT:HyperDT()
	if ActivateHyperMode then
		ActivateHyperMode = nil
		DT:LoadDataTexts()
	else
		ActivateHyperMode = true
		DT:EnableHyperMode()
	end
end

function DT:RegisterHyperDT()
	for name, info in pairs(DT.RegisteredDataTexts) do
		local category = DT:GetMenuListCategory(info.category or MISCELLANEOUS)
		if not category then
			category = #HyperList + 1
			tinsert(HyperList, { text = info.category or MISCELLANEOUS, notCheckable = true, hasArrow = true, menuList = {} } )
		end

		tinsert(HyperList[category].menuList, { text = info.localizedName or name, checked = function() return DT.EasyMenu.MenuGetItem(DT.SelectedDatatext, name) end, func = function() DT.EasyMenu.MenuSetItem(DT.SelectedDatatext, name) end })
	end

	DT:SortMenuList(HyperList)
	tinsert(HyperList, { text = L["NONE"], checked = function() return DT.EasyMenu.MenuGetItem(DT.SelectedDatatext, '') end, func = function() DT.EasyMenu.MenuSetItem(DT.SelectedDatatext, '') end })

	DT:RegisterEvent('MODIFIER_STATE_CHANGED', 'SingleHyperMode')
end

function DT:Initialize()
	DT.Initialized = true
	DT.db = E.db.datatexts

	DT.tooltip = CreateFrame('GameTooltip', 'DataTextTooltip', E.UIParent, 'GameTooltipTemplate')
	DT.EasyMenu = CreateFrame("Frame", "DataTextEasyMenu", E.UIParent, "UIDropDownMenuTemplate")
	DT.HyperDTMenuFrame = DT.EasyMenu
	DT.EasyMenu:SetClampedToScreen(true)
	DT.EasyMenu:EnableMouse(true)
	DT.EasyMenu.MenuSetItem = function(dt, value)
		DT.db.panels[dt.parentName][dt.pointIndex] = value
		DT:UpdatePanelInfo(dt.parentName, dt.parent)

		if ActivateHyperMode then
			DT:EnableHyperMode(dt.parent)
		end

		DT.SelectedDatatext = nil
		CloseDropDownMenus()
	end
	DT.EasyMenu.MenuGetItem = function(dt, value)
		return dt and (DT.db.panels[dt.parentName] and DT.db.panels[dt.parentName][dt.pointIndex] == value)
	end

	TT:HookScript(DT.tooltip, 'OnShow', 'SetStyle')

	-- Ignore header font size on DatatextTooltip
	local font = E.Libs.LSM:Fetch('font', E.db.tooltip.font)
	local fontOutline = E.db.tooltip.fontOutline
	local textSize = E.db.tooltip.textFontSize
	_G.DataTextTooltipTextLeft1:FontTemplate(font, textSize, fontOutline)
	_G.DataTextTooltipTextRight1:FontTemplate(font, textSize, fontOutline)

	LDB.RegisterCallback(E, 'LibDataBroker_DataObjectCreated', DT.SetupObjectLDB)
	DT:RegisterLDB() -- LibDataBroker

	for name, db in pairs(E.global.datatexts.customPanels) do
		DT:BuildPanelFrame(name, db, true)
	end

	do -- we need to register the panels to access them for the text
		DT.BattleStats.LEFT.panel = _G.LeftChatDataPanel.dataPanels
		DT.BattleStats.RIGHT.panel = _G.RightChatDataPanel.dataPanels
	end

	DT:RegisterEvent('PLAYER_ENTERING_WORLD', 'LoadDataTexts')

	DT:RegisterHyperDT()
end

--[[
	DT:RegisterDatatext(name, events, eventFunc, updateFunc, clickFunc, onEnterFunc, onLeaveFunc, localizedName)

	name - name of the datatext (required)
	category - name of the category the datatext belongs to.
	events - must be a table with string values of event names to register
	eventFunc - function that gets fired when an event gets triggered
	updateFunc - onUpdate script target function
	click - function to fire when clicking the datatext
	onEnterFunc - function to fire OnEnter
	onLeaveFunc - function to fire OnLeave, if not provided one will be set for you that hides the tooltip.
	localizedName - localized name of the datetext
	objectEvent - register events on an object, using E.RegisterEventForObject instead of panel.RegisterEvent
]]
function DT:RegisterDatatext(name, category, events, eventFunc, updateFunc, clickFunc, onEnterFunc, onLeaveFunc, localizedName, objectEvent)
	if not name then error('Cannot register datatext no name was provided.') end
	local data = {name = name, category = category}

	if type(events) ~= 'table' and events ~= nil then
		error('Events must be registered as a table.')
	else
		data.events = events
		data.eventFunc = eventFunc
		data.objectEvent = objectEvent
	end

	if updateFunc and type(updateFunc) == 'function' then
		data.onUpdate = updateFunc
	end

	if clickFunc and type(clickFunc) == 'function' then
		data.onClick = clickFunc
	end

	if onEnterFunc and type(onEnterFunc) == 'function' then
		data.onEnter = onEnterFunc
	end

	if onLeaveFunc and type(onLeaveFunc) == 'function' then
		data.onLeave = onLeaveFunc
	end

	if localizedName and type(localizedName) == 'string' then
		data.localizedName = localizedName
	end

	DT.RegisteredDataTexts[name] = data

	return data
end

E:RegisterModule(DT:GetName())
