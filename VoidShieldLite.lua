--[[ Void Shield Lite
  Tells you when your Void Shield is worth casting: you have a Void Shield proc (Master the
  Darkness) AND Weal and Woe is at 7+ stacks.
    proc + 7 stacks  : a glowing cartoon void vortex pops up and spins, the stack count on its
                       left edge, and one chime
    proc + 10 stacks : it supercharges into a purple phoenix (wings, flames, lightning, sparks, a
                       strong glow) and the chime cascades upward three times (or the bird / ocean
                       sound pack's version)
  No proc = no square, no sound. 8 and 9 are silent. Nothing in the addon runs every frame: the
  effects are the game's own animations, and they only play while the square is showing.

  Raids, dungeons & M+ hide buff details from addons (they can't read the number). There:
    The number in the square is drawn by the game itself, so it matches your buff exactly.
    Void Shield proc : read from your Power Word: Shield button. While you have a proc the
                       game turns it into Void Shield, whatever gave you the proc (Mind Blast,
                       Shadow Word: Pain, Penance), and it stays Void Shield while a 2nd is left
    Weal and Woe     : each Penance adds your stacks (7 by default, or measured), bolt by bolt;
                       Ultimate Penitence fills it to 10 across its barrage;
                       casting a shield uses them all up ]]

local ADDON, ns = ...
local M = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
local FONT = "Fonts\\FRIZQT__.TTF"
local SIZE = 56
local NUM_SIZE = 30               -- the stack number, on the left edge of the square
local NUM_X = 3                   -- how far the number tucks over the square's left edge
local MAX, WW_DURATION, VS_DURATION, VS_MAX = 10, 20, 30, 2
local WW_TALENT, WW_GUESS = 390786, 390787
local VS_TALENTS = { [1253590] = true, [1253845] = true, [1253827] = true }
local VOID_SHIELD_ID, PWS_ID, MIND_BLAST_ID, RADIANCE_ID = 1253593, 17, 8092, 194509
local ULTIMATE_PENITENCE_ID = 421453
local GetTime, pcall, ipairs, pairs, type = GetTime, pcall, ipairs, pairs, type
local floor, min, max = math.floor, math.min, math.max

local DEFAULTS = { threshold = 7, sound = true, maxSound = true, channel = "Master", scale = 1,
                   point = "CENTER", relPoint = "CENTER", x = 0, y = -120,
                   bolts = nil, debug = false, pack = "chimes", fx = true }

-- sound packs: one sound at the threshold (7), a bigger one at 10
local PACKS = {
	{ key = "chimes", name = "Chimes", ready = "ready", max = "max",
	  about = "harp chime; at 10 it cascades up three times into a shower of sparkles" },
	{ key = "birds", name = "Birdsong", ready = "bird_ready", max = "bird_max",
	  about = "a little songbird; at 10 it sings higher and higher into a dawn chorus" },
	{ key = "ocean", name = "Ocean", ready = "ocean_ready", max = "ocean_max",
	  about = "sonar ping; at 10 rising pings, bubbles, dolphins and a whale call" },
}
local PACK_ALIASES = { chime = "chimes", bird = "birds", birdsong = "birds", sea = "ocean",
                       whale = "ocean", dolphin = "ocean", sonar = "ocean" }
local db
local anchor, sq                  -- the square (built at login)

local isSecret = issecretvalue or function() return false end
local function Readable(v) if isSecret(v) then return false end return v ~= nil end
local function Field(t, k) local ok, v = pcall(function() return t[k] end) if ok then return v end end
local function Print(m) print("|cffb070ffVoid Shield|r Lite: " .. m) end
local function Debug(m) if db and db.debug then Print("|cff999999" .. m .. "|r") end end
local function SpellName(id)
	local ok, n = pcall(C_Spell.GetSpellName, id)
	if ok and Readable(n) then return n end
end

-- true wherever the game hides buff details from addons (combat restrictions, encounters, M+)
local function Hidden()
	if C_Secrets and C_Secrets.ShouldAurasBeSecret then
		local ok, v = pcall(C_Secrets.ShouldAurasBeSecret)
		if ok and v == true then return true end
	end
	local RA, T = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if RA and RA.IsAddOnRestrictionActive and T then
		for _, k in ipairs({ "Combat", "Encounter", "ChallengeMode" }) do
			if T[k] ~= nil then
				local ok, v = pcall(RA.IsAddOnRestrictionActive, T[k])
				if ok and v == true then return true end
			end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The two buffs: Weal and Woe (stacks) and Master the Darkness (your Void Shield proc)
-- Neither buff's spell ID is published, so they're found by name and confirmed from your
-- buffs wherever those are readable.
---------------------------------------------------------------------------
local B = {
	ww = { ids = {}, nameFrom = WW_TALENT, fallbackName = "Weal and Woe", ranges = { { 390700, 390900 }, { 1240000, 1270000 } },
	       skip = { [WW_TALENT] = true }, guess = WW_GUESS, key = "wwBuffID" },
	vs = { ids = {}, nameFrom = 1253590, fallbackName = "Master the Darkness", ranges = { { 1253400, 1254100 } },
	       skip = VS_TALENTS, key = "vsBuffID" },
}
local castNames = { penance = {}, shield = {}, mindblast = {}, ultimate = {} }

local function FindIDs()
	for _, b in pairs(B) do
		b.name = SpellName(b.nameFrom) or b.fallbackName
		local seen = {}
		b.ids = {}
		local function add(id) if id and not seen[id] and not b.skip[id] then seen[id] = true b.ids[#b.ids + 1] = id end end
		add(db[b.key])
		for _, r in ipairs(b.ranges) do
			for id = r[1], r[2] do
				if SpellName(id) == b.name then
					local ok, passive = pcall(C_Spell.IsSpellPassive, id)
					if not (ok and passive == true) then add(id) end
				end
			end
		end
		add(b.guess)
	end
	castNames = { penance = {}, shield = {}, mindblast = {}, ultimate = {} }
	for kind, list in pairs({ penance = { 47540, 400169 }, shield = { PWS_ID, VOID_SHIELD_ID }, mindblast = { MIND_BLAST_ID, 450405 }, ultimate = { ULTIMATE_PENITENCE_ID } }) do
		for _, id in ipairs(list) do local n = SpellName(id) if n then castNames[kind][n] = true end end
	end
	castNames.mindblast["Mind Blast"], castNames.mindblast["Void Blast"] = true, true
	castNames.ultimate["Ultimate Penitence"] = true
	B.vs.spellName = SpellName(VOID_SHIELD_ID) or "Void Shield"
end

local function Learn()
	if db.wwBuffID and db.vsBuffID then return end
	for i = 1, 60 do
		local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or isSecret(a) or not a then return end
		local name, id, dur = Field(a, "name"), Field(a, "spellId"), Field(a, "duration")
		if Readable(name) and Readable(id) and Readable(dur) and dur > 0 then
			for _, b in pairs(B) do
				if not db[b.key] and name == b.name and not b.skip[id] then
					db[b.key] = id
					FindIDs()
					ns.engineDirty = true
					Debug(("confirmed %s = spell %d"):format(b.name, id))
				end
			end
		end
	end
end

-- stacks (0 if absent), or nil if the game is hiding it
local function Read(b)
	for _, id in ipairs(b.ids) do
		local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
		if not ok or isSecret(a) then return nil end
		if a then
			local apps, dur = Field(a, "applications"), Field(a, "duration")
			if not Readable(apps) or not Readable(dur) then return nil end
			if dur > 0 then return max(1, apps) end
		end
	end
	return 0
end

---------------------------------------------------------------------------
-- Your Power Word: Shield button: it becomes Void Shield while you hold a proc.
-- returns true (proc up), false (no proc), or nil (can't tell)
---------------------------------------------------------------------------
local function ShieldIsVoid()
	local id
	if C_Spell and C_Spell.GetOverrideSpell then
		local ok, v = pcall(C_Spell.GetOverrideSpell, PWS_ID)
		if ok and Readable(v) and type(v) == "number" then id = v end
	end
	if not id and FindSpellOverrideByID then
		local ok, v = pcall(FindSpellOverrideByID, PWS_ID)
		if ok and Readable(v) and type(v) == "number" then id = v end
	end
	if not id then return nil end
	if id == VOID_SHIELD_ID or SpellName(id) == B.vs.spellName then return true end
	if id == PWS_ID or id == 0 then return false end
	return nil
end

---------------------------------------------------------------------------
-- Counting from your casts (used where the game hides the buffs)
---------------------------------------------------------------------------
local est = { ww = 0, wwExp = 0, vs = 0, vsExp = 0 }
local chan, radiancePending = nil, 0
local exact = { ww = nil, vs = nil }       -- last readable values (for learning)
local Update

local function IsCast(kind, spellID)
	if not Readable(spellID) then return false end
	if kind == "shield" and (spellID == PWS_ID or spellID == VOID_SHIELD_ID) then return true end
	if kind == "mindblast" and spellID == MIND_BLAST_ID then return true end
	local n = SpellName(spellID)
	return n and castNames[kind][n] or false
end

---------------------------------------------------------------------------
-- Stacks per Penance, remembered per talent build (some talents add Penance bolts, e.g. a
-- Kings' Rest build). Each build is measured where stacks are visible, or set by hand.
---------------------------------------------------------------------------
local buildKey = "default"
local function BuildKey()
	if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo) then return "default" end
	local ok, cfg = pcall(C_ClassTalents.GetActiveConfigID)
	if not ok or type(cfg) ~= "number" then return "default" end
	local okI, info = pcall(C_Traits.GetConfigInfo, cfg)
	if not okI or type(info) ~= "table" or type(info.treeIDs) ~= "table" then return "default" end
	local h = 0
	for _, tree in ipairs(info.treeIDs) do
		local okN, nodes = pcall(C_Traits.GetTreeNodes, tree)
		for _, node in ipairs(okN and nodes or {}) do
			local okD, ni = pcall(C_Traits.GetNodeInfo, cfg, node)
			if okD and type(ni) == "table" and (ni.activeRank or 0) > 0 then
				local entry = (ni.activeEntry and ni.activeEntry.entryID) or 0
				h = (h * 31 + node * 7 + entry * 3 + ni.activeRank) % 2147483629
			end
		end
	end
	return tostring(h)
end
local function BuildData()
	db.builds = db.builds or {}
	db.builds[buildKey] = db.builds[buildKey] or {}
	return db.builds[buildKey]
end
local function StacksPerPenance()
	local b = BuildData()
	return b.bolts or 7          -- she told us her Penance gives 7; each build is measured for real
end
local function RefreshBuild(announce)
	local key = BuildKey()
	if key == buildKey then return end
	buildKey = key
	local b = BuildData()
	if announce then
		Print(("talents changed: one Penance = %d stacks for this build%s"):format(StacksPerPenance(),
			b.locked and " (set by you)" or (b.bolts and " (measured)" or " (default). If it's different with these talents, type /vsv stacks N")))
	end
end

local function EstStack(token)
	if not chan or chan.token ~= token then return end
	local now = GetTime()
	est.ww = min(MAX, (est.wwExp > now and est.ww or 0) + 1)
	est.wwExp = now + WW_DURATION
	chan.counted = (chan.counted or 0) + 1
	Update()
end

local function PenanceStart(ultimate)
	local now = GetTime()
	if chan and now - chan.start < 0.4 and chan.ultimate == ultimate then return end
	local dur = ultimate and 6 or 2
	local ok, _, _, _, st, en = pcall(UnitChannelInfo, "player")
	if ok and Readable(st) and Readable(en) and en > st then dur = (en - st) / 1000 end
	-- Ultimate Penitence's barrage takes you all the way to 10
	local n = ultimate and MAX or max(1, floor(StacksPerPenance() + 0.5))
	local fighting = InCombatLockdown() or (UnitAffectingCombat and UnitAffectingCombat("player") == true)
	chan = { token = {}, start = now, dur = dur, n = n, from = (not ultimate and fighting) and exact.ww or nil, ultimate = ultimate }
	if Hidden() then
		local tok = chan.token
		local timing = (not ultimate) and BuildData().timing or nil
		for k = 0, n - 1 do
			local at
			if timing and timing[k + 1] then at = timing[k + 1] * dur                -- her real timing
			else at = (n > 1) and (k * dur / (n - 1)) * 0.92 or 0 end               -- evenly spread
			if at <= 0.01 then EstStack(tok) else C_Timer.After(at, function() EstStack(tok) end) end
		end
	end
	if chan.from then chan.gains = {} end          -- record when her stacks arrive (open-world combat)
end

local function PenanceStop()
	if not chan then return end
	local c = chan
	local full = (GetTime() - c.start) >= c.dur * 0.8
	-- the channel finished (or nearly): any bolts not counted yet did land
	if full and Hidden() and (c.counted or 0) < c.n then
		local now = GetTime()
		est.ww = min(MAX, (est.wwExp > now and est.ww or 0) + (c.n - (c.counted or 0)))
		est.wwExp = now + WW_DURATION
	end
	chan = nil
	-- measure her real stacks per Penance: only in combat (Twinsight's extra bolts depend on a
	-- nearby ally/enemy), only from a fresh start (0 stacks), most common of the last 5 results
	if c.from == 0 and full and not BuildData().locked then
		C_Timer.After(0.4, function()
			local now = exact.ww
			if not now or now < 1 or now >= MAX then return end   -- capped at 10: can't tell the full gain
			local b = BuildData()
			b.samples = b.samples or {}
			table.insert(b.samples, now)
			while #b.samples > 5 do table.remove(b.samples, 1) end
			local count, best, bestN = {}, nil, 0
			for i, v in ipairs(b.samples) do
				count[v] = (count[v] or 0) + 1
				if count[v] >= bestN then best, bestN = v, count[v] end
			end
			local changed = b.bolts ~= best
			b.bolts = best
			if c.gains and #c.gains == now then
				b.timing = b.timing or {}
				for k, f in ipairs(c.gains) do
					b.timing[k] = b.timing[k] and (b.timing[k] * 0.6 + f * 0.4) or f
				end
				for k = #c.gains + 1, #b.timing do b.timing[k] = nil end
				Debug("measured when each stack arrives during your Penance")
			end
			Debug(("measured: one Penance gives %d stacks (this talent build)"):format(best))
			if changed then Print(("measured: one Penance gives %d stacks with this talent build"):format(best)) end
		end)
	end
end

---------------------------------------------------------------------------
-- Reading the game's own hidden aura frames (only trusted once proven to work)
---------------------------------------------------------------------------
local engineParent, container, engineSig, engineOK
local probe = { ww = nil, vs = nil, wwProven = false, vsProven = false }

local function ProbeVisible(fs)
	if not fs then return nil end
	local ok, vis = pcall(fs.IsVisible, fs)
	if not ok or type(vis) ~= "boolean" then return nil end
	return vis
end
-- Weal and Woe probe: our badge font draws nothing below the threshold, a normal width for
-- threshold..9 and a wider glyph for 10, so its width tells us the band
local function WWBand()
	if not (engineParent and engineParent:IsShown()) then return nil end
	local vis = ProbeVisible(probe.ww)
	if vis == nil then return nil end
	local w = 0
	if vis then
		local ok, ww = pcall(probe.ww.GetStringWidth, probe.ww)
		if not ok or isSecret(ww) or type(ww) ~= "number" then return nil end
		w = ww
	end
	if w >= 1 then probe.wwProven = true end
	if not probe.wwProven then return nil end
	if w < 1 then return 0 end
	return (w > NUM_SIZE * 1.25) and MAX or db.threshold
end
local function VSPresent()
	if not (engineParent and engineParent:IsShown()) then return nil end
	local vis = ProbeVisible(probe.vs)
	if vis == nil then return nil end
	if vis then probe.vsProven = true end
	if not probe.vsProven then return nil end
	return vis
end

local function EngineSupported()
	if engineOK ~= nil then return engineOK end
	engineOK = false
	if C_AuraContainerUtil then
		local ok, f = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
		if ok and f then f:Hide() engineOK = true end
	end
	return engineOK
end

local function BuildEngine()
	if not EngineSupported() or InCombatLockdown() then return end
	if #B.ww.ids == 0 and #B.vs.ids == 0 then return end
	local sig = table.concat(B.ww.ids, ",") .. "|" .. table.concat(B.vs.ids, ",") .. ":" .. db.threshold
	if sig == engineSig then ns.engineDirty = nil return end
	if not engineParent then
		-- sits exactly on the square; only made visible while the square is showing
		engineParent = CreateFrame("Frame", nil, anchor)
		engineParent:SetSize(SIZE, SIZE)
		engineParent:SetPoint("CENTER", anchor, "CENTER", 0, 0)
		engineParent:SetFrameStrata("HIGH")
		engineParent:SetFrameLevel(sq:GetFrameLevel() + 10)
		engineParent:SetAlpha(0)
		engineParent:Hide()
	end
	local ok = pcall(function()
		if container then container:Hide() end
		probe.ww, probe.vs, probe.wwProven, probe.vsProven = nil, nil, false, false
		container = CreateFrame("AuraContainer", nil, engineParent, "CustomAuraContainerTemplate")
		container:SetPoint("TOPLEFT")
		container:SetUnit("player")
		local function group(key, ids, init, index)
			local set = {}
			for _, id in ipairs(ids) do set[id] = true end
			if not next(set) then return end
			container:AddAuraGroup(key, "HELPFUL", {
				maxFrameCount = 1,
				candidateFilters = { includeSpellIDs = set },
				initializeFrame = init,
				layout = { elementWidth = SIZE, elementHeight = SIZE, elementSpacing = 0, lineSpacing = 0,
				           elementSpacingX = 0, elementSpacingY = 0, layoutIndex = index },
			})
		end
		group("wealwoe", B.ww.ids, function(button)
			button:SetSize(SIZE, SIZE)
			local icon = button:CreateTexture(nil, "ARTWORK") icon:SetSize(1, 1) icon:SetPoint("CENTER") icon:SetAlpha(0)
			button:SetIcon(icon)
			-- the game writes her real Weal and Woe count here (our font draws nothing below 7)
			local count = button:CreateFontString(nil, "OVERLAY")
			count:SetFont(M .. "num" .. db.threshold .. ".ttf", NUM_SIZE, "THICKOUTLINE")
			count:SetPoint("RIGHT", button, "LEFT", NUM_X, 0)
			count:SetTextColor(1, 0.9, 0.4)
			button:SetApplicationCount(count)
			probe.ww = count
		end, 1)
		group("voidshield", B.vs.ids, function(button)
			button:SetSize(SIZE, SIZE)
			local icon = button:CreateTexture(nil, "ARTWORK") icon:SetSize(1, 1) icon:SetPoint("CENTER") icon:SetAlpha(0)
			button:SetIcon(icon)
			local mark = button:CreateFontString(nil, "OVERLAY")
			mark:SetFont(FONT, 8, "") mark:SetPoint("CENTER") mark:SetText("x") mark:SetAlpha(0)
			probe.vs = mark
		end, 2)
		container:Show()
	end)
	if ok then engineSig, ns.engineDirty = sig, nil end
end

---------------------------------------------------------------------------
-- Sound
---------------------------------------------------------------------------
local function Pack()
	for _, p in ipairs(PACKS) do if p.key == db.pack then return p end end
	return PACKS[1]
end
local soundHandle
-- stopPrevious: the 10-stack sound gently fades out a 7-stack sound that's still ringing
local function PlayFile(file, stopPrevious)
	if stopPrevious and soundHandle and StopSound then pcall(StopSound, soundHandle, 300) end
	local ok, willPlay, handle = pcall(PlaySoundFile, M .. file .. ".ogg", db.channel)
	soundHandle = (ok and willPlay) and handle or nil
end
local function Play(kind) if db.sound then PlayFile(Pack()[kind], kind == "max") end end

---------------------------------------------------------------------------
-- The square: a cartoon force-field shield. At 10 stacks it bursts into a phoenix: wings, flames,
-- lightning, sparks and a glow. These are the game's own animations (no per-frame addon code);
-- they're built once at login and only play while the square shows.
---------------------------------------------------------------------------
local fx = { all = {}, bolts = {}, sparks = {}, embers = {} }
local look, fxToken = 0, nil          -- look: 0 hidden, 1 void vortex (threshold), 2 phoenix (10)
local VORTEX = 0.82                   -- the vortex's size in the box's window

-- angle, length (x box), texture, first flash (sec), pause between flashes
local BOLTS = { { 28, 1.05, "bolt1", 0.05, 0.95 }, { 152, 0.95, "bolt2", 0.45, 1.3 },
                { 208, 1.0, "bolt1", 0.8, 1.1 }, { 334, 0.9, "bolt2", 0.25, 1.45 } }
local SPARKS = { 15, 62, 118, 170, 238, 292, 322 }
local EMBERS = { { -0.30, 0.9, 0.1 }, { 0.08, 1.1, 0.45 }, { 0.36, 0.8, 0.75 } }   -- x, size, first

local function Tex(parent, file, layer, sub, w, h, blend)
	local t = parent:CreateTexture(nil, layer, nil, sub)
	t:SetTexture(M .. file)
	t:SetSize(w, h)
	t:SetPoint("CENTER")
	if blend then t:SetBlendMode(blend) end
	t:SetAlpha(0)
	return t
end
local function Group(region, looping)
	local g = region:CreateAnimationGroup()
	if looping then g:SetLooping(looping) end
	fx.all[#fx.all + 1] = g
	return g
end
local function Anim(g, kind, dur, order, smoothing, endDelay)
	local a = g:CreateAnimation(kind)
	a:SetDuration(dur)
	a:SetOrder(order or 1)
	if smoothing then a:SetSmoothing(smoothing) end
	if endDelay then a:SetEndDelay(endDelay) end
	return a
end
local function Fade(g, from, to, dur, order, smoothing, endDelay)
	local a = Anim(g, "Alpha", dur, order, smoothing, endDelay)
	a:SetFromAlpha(from) a:SetToAlpha(to)
	return a
end
local function Grow(g, from, to, dur, order, smoothing, endDelay, fromY, toY)
	local a = Anim(g, "Scale", dur, order, smoothing, endDelay)
	fromY, toY = fromY or from, toY or to
	if a.SetScaleFrom then a:SetScaleFrom(from, fromY) a:SetScaleTo(to, toY)
	else a:SetFromScale(from, fromY) a:SetToScale(to, toY) end
	return a
end
local function Move(g, dx, dy, dur, order, smoothing, endDelay)
	local a = Anim(g, "Translation", dur, order, smoothing, endDelay)
	a:SetOffset(dx, dy)
	return a
end
local function Spin(g, degrees, dur, order, smoothing, endDelay)
	local a = Anim(g, "Rotation", dur, order, smoothing, endDelay)
	a:SetDegrees(degrees)
	return a
end

local function BuildArt()
	local B, rad, cos, sin = SIZE, math.rad, math.cos, math.sin
	-- behind the box: its glow (soft at the threshold, strong at 10), then the phoenix wings + flames
	fx.glow = Tex(sq.back, "glow", "BACKGROUND", 0, 2.1 * B, 2.1 * B, "ADD")
	fx.wings = Tex(sq.back, "wings", "BORDER", 0, 3.3 * B, 1.65 * B)
	fx.wings:SetPoint("CENTER", 0, 0.04 * B)
	fx.flames1 = Tex(sq.back, "flames1", "ARTWORK", 1, 1.9 * B, 1.9 * B)
	fx.flames2 = Tex(sq.back, "flames2", "ARTWORK", 2, 1.9 * B, 1.9 * B)
	-- the box: frame, the void vortex spinning in its window (calm / supercharged), a light layer
	-- over the vortex, a glass shine, and a white flash for the transformation
	fx.frame = Tex(sq.art, "frame", "ARTWORK", 0, B, B)
	fx.frameMax = Tex(sq.art, "frame_max", "ARTWORK", 1, B, B)
	fx.vortex = Tex(sq.art, "vortex", "ARTWORK", 2, VORTEX * B, VORTEX * B)
	fx.vortexMax = Tex(sq.art, "vortex_max", "ARTWORK", 3, VORTEX * B, VORTEX * B)
	fx.vortexGlow = Tex(sq.art, "vortex_glow", "ARTWORK", 4, VORTEX * B, VORTEX * B, "ADD")
	fx.vortexGlow:SetVertexColor(0.7, 0.45, 1)
	fx.gloss = Tex(sq.art, "gloss", "ARTWORK", 5, B, B)
	fx.flash = Tex(sq.art, "boxmask", "OVERLAY", 0, B, B, "ADD")
	-- in front: shockwave ring, a twinkle on the glass, lightning, sparks, embers
	fx.ring = Tex(sq.front, "ring", "ARTWORK", 0, 1.2 * B, 1.2 * B, "ADD")
	fx.ring:SetVertexColor(0.8, 0.6, 1)
	fx.twinkle = Tex(sq.front, "spark", "OVERLAY", 2, 0.26 * B, 0.26 * B, "ADD")
	fx.twinkle:SetPoint("CENTER", -0.30 * B, 0.32 * B)

	-- the vortex spins forever (slowly at the threshold, fast at 10). It pops in with a 72 degree
	-- twist first; its 5 arms make that look identical to 0, so the spin takes over seamlessly
	local function Spinner(region, pop, popFrom, period)
		local p = Group(region)
		Grow(p, popFrom, 1, pop, 1, "OUT") Spin(p, -72, pop, 1, "OUT")
		local s = Group(region, "REPEAT")
		Spin(s, -360, period, 1)
		p:SetScript("OnFinished", function(_, requested) if not requested and look ~= 0 then s:Play() end end)
		return p, s
	end
	fx.popVortex, fx.spinVortex = Spinner(fx.vortex, 0.24, 0.6, 9)
	fx.popVortexMax, fx.spinVortexMax = Spinner(fx.vortexMax, 0.35, 1.45, 3)
	fx.popGlow, fx.spinGlow = Spinner(fx.vortexGlow, 0.24, 0.6, 9)
	fx.popGlowMax, fx.spinGlowMax = Spinner(fx.vortexGlow, 0.35, 1.45, 3)
	local function Pop(region, from, dur)
		local g = Group(region)
		Grow(g, from, 1, dur, 1, "OUT")
		return g
	end

	-- threshold: the box pops in, glows softly, and its glass twinkles now and then
	fx.popFrame, fx.popGloss = Pop(fx.frame, 0.6, 0.24), Pop(fx.gloss, 0.6, 0.24)
	fx.calmGlow = Group(fx.glow, "BOUNCE")
	Fade(fx.calmGlow, 0.3, 0.55, 1.6, 1, "IN_OUT") Grow(fx.calmGlow, 0.97, 1.03, 1.6, 1, "IN_OUT")
	fx.twinkleLoop = Group(fx.twinkle, "REPEAT")
	Grow(fx.twinkleLoop, 0.3, 1, 0.16, 1, "OUT") Fade(fx.twinkleLoop, 0, 1, 0.16, 1) Spin(fx.twinkleLoop, -45, 0.16, 1)
	Fade(fx.twinkleLoop, 1, 0, 0.45, 2, "IN", 2.6) Spin(fx.twinkleLoop, -60, 0.45, 2, nil, 2.6)

	-- 10 stacks: flash, shockwave, the box pops then throbs, glow breathes hard, wings unfurl and
	-- flap, the flame crown flickers (two drawings cross-fading at different speeds)
	fx.flashAnim = Group(fx.flash) Fade(fx.flashAnim, 0.9, 0, 0.45, 1, "OUT")
	fx.ringAnim = Group(fx.ring)
	Grow(fx.ringAnim, 0.7, 2.6, 0.6, 1, "OUT") Fade(fx.ringAnim, 1, 0, 0.6, 1, "IN")
	fx.popFrameMax, fx.popGlossMax = Pop(fx.frameMax, 1.45, 0.35), Pop(fx.gloss, 1.45, 0.35)
	fx.pulse = Group(fx.frameMax, "BOUNCE") Grow(fx.pulse, 1, 1.07, 0.5, 1, "IN_OUT")
	fx.glowLoop = Group(fx.glow, "BOUNCE")
	Fade(fx.glowLoop, 0.55, 1, 0.8, 1, "IN_OUT") Grow(fx.glowLoop, 0.96, 1.06, 0.8, 1, "IN_OUT")
	fx.wingsIn = Group(fx.wings)
	Grow(fx.wingsIn, 0.2, 1, 0.42, 1, "OUT") Fade(fx.wingsIn, 0, 1, 0.2, 1)
	fx.wingsLoop = Group(fx.wings, "BOUNCE")
	Grow(fx.wingsLoop, 1, 1.04, 0.75, 1, "IN_OUT", nil, 1, 0.9):SetOrigin("BOTTOM", 0, 0)
	Fade(fx.wingsLoop, 1, 0.82, 0.75, 1, "IN_OUT")
	fx.flames1Loop = Group(fx.flames1, "BOUNCE")
	Fade(fx.flames1Loop, 1, 0.4, 0.21, 1, "IN_OUT")
	Grow(fx.flames1Loop, 1, 1, 0.21, 1, "IN_OUT", nil, 1, 1.07):SetOrigin("BOTTOM", 0, 0)
	fx.flames2Loop = Group(fx.flames2, "BOUNCE")
	Fade(fx.flames2Loop, 0.25, 1, 0.29, 1, "IN_OUT")
	Grow(fx.flames2Loop, 1.03, 0.98, 0.29, 1, "IN_OUT", nil, 1, 1.05):SetOrigin("BOTTOM", 0, 0)
	-- once the pop / unfurl is done, the gentle loops take over
	fx.popFrameMax:SetScript("OnFinished", function(_, requested)
		if not requested and look == 2 then fx.pulse:Play() end
	end)
	fx.wingsIn:SetScript("OnFinished", function(_, requested)
		if not requested and look == 2 then fx.wingsLoop:Play() end
	end)

	-- lightning crackling out of the shield: flash, flicker, fade, pause (each at its own pace)
	for i, b in ipairs(BOLTS) do
		local a, len = rad(b[1]), b[2]
		local side, r = 0.95 * B * len, B * (0.5 + 0.42 * len)
		local t = Tex(sq.front, b[3], "ARTWORK", 1, side, side, "ADD")
		t:SetPoint("CENTER", cos(a) * r, sin(a) * r)
		t:SetRotation(a)
		t:SetVertexColor(0.82, 0.72, 1)
		local g = Group(t, "REPEAT")
		Fade(g, 0, 1, 0.03, 1) Fade(g, 1, 0.25, 0.05, 2) Fade(g, 0.25, 1, 0.04, 3) Fade(g, 1, 0, 0.16, 4, "IN", b[5])
		fx.bolts[i] = { g = g, first = b[4] }
	end
	-- sparks flying out from the edges
	for i, deg in ipairs(SPARKS) do
		local a = rad(deg)
		local t = Tex(sq.front, "spark", "OVERLAY", 1, 0.3 * B, 0.3 * B, "ADD")
		t:SetPoint("CENTER", cos(a) * 0.55 * B, sin(a) * 0.55 * B)
		if i % 3 == 0 then t:SetVertexColor(1, 0.75, 1) else t:SetVertexColor(0.92, 0.82, 1) end
		local g = Group(t, "REPEAT")
		local d, rest = 0.62 + (i % 3) * 0.08, 0.28 + (i % 2) * 0.12
		Move(g, cos(a) * 0.6 * B, sin(a) * 0.6 * B, d, 1, "OUT", rest)
		Fade(g, 1, 0, d, 1, "IN", rest)
		Grow(g, 1.1, 0.35, d, 1, nil, rest)
		fx.sparks[i] = { g = g, first = (i - 1) * 0.11 }
	end
	-- purple phoenix flames rising off the top of the box
	for i, e in ipairs(EMBERS) do
		local x, s = e[1], e[2]
		local t = Tex(sq.front, "flame", "ARTWORK", 2, 0.18 * B * s, 0.36 * B * s)
		t:SetPoint("CENTER", x * B, 0.42 * B)
		local g = Group(t, "REPEAT")
		Fade(g, 0, 0.95, 0.15, 1) Move(g, 0, 0.1 * B, 0.15, 1)
		Fade(g, 0.95, 0, 0.7, 2, "IN", 0.25) Move(g, x * 0.2 * B, 0.45 * B, 0.7, 2, "OUT", 0.25)
		Grow(g, 1, 0.45, 0.7, 2, nil, 0.25)
		fx.embers[i] = { g = g, first = e[3] }
	end
end

local function StartLater(sec, g)
	local tok = fxToken
	C_Timer.After(sec, function() if fxToken == tok and look == 2 then g:Play() end end)
end

-- show the square as: 0 hidden, 1 void shield, 2 phoenix
local function SetLook(new)
	local old = look
	look = new
	fxToken = {}                                   -- cancels staggered starts still waiting
	for _, g in ipairs(fx.all) do g:Stop() end
	if new == 0 then sq:Hide() return end
	local hot, animate = new == 2, db.fx
	local flame = (hot and animate) and 1 or 0
	fx.frame:SetAlpha(hot and 0 or 1) fx.frameMax:SetAlpha(hot and 1 or 0)
	fx.vortex:SetAlpha(hot and 0 or 1) fx.vortexMax:SetAlpha(hot and 1 or 0)
	fx.vortexGlow:SetAlpha(hot and 0.55 or 0.25) fx.gloss:SetAlpha(1)
	-- the glow: soft violet at the threshold, strong at 10 (it breathes while animating)
	if hot then fx.glow:SetVertexColor(0.62, 0.3, 1) else fx.glow:SetVertexColor(0.55, 0.3, 1) end
	fx.glow:SetAlpha(hot and 0.85 or 0.4)
	fx.wings:SetAlpha(flame) fx.flames1:SetAlpha(flame) fx.flames2:SetAlpha(flame)
	sq.numBack:SetAlpha(hot and 0.65 or 0.45)
	sq:Show()
	if not animate then return end
	fx.twinkleLoop:Play()
	if not hot then
		fx.calmGlow:Play()
		if old == 0 then
			fx.popVortex:Play() fx.popGlow:Play() fx.popFrame:Play() fx.popGloss:Play()
		else
			fx.spinVortex:Play() fx.spinGlow:Play()
		end
		return
	end
	fx.popVortexMax:Play() fx.popGlowMax:Play() fx.popFrameMax:Play() fx.popGlossMax:Play()
	fx.flashAnim:Play() fx.ringAnim:Play() fx.glowLoop:Play()
	fx.wingsIn:Play() fx.flames1Loop:Play() fx.flames2Loop:Play()
	for _, list in ipairs({ fx.bolts, fx.sparks, fx.embers }) do
		for _, s in ipairs(list) do StartLater(s.first, s.g) end
	end
end
function ns:RefreshLook() if look ~= 0 then SetLook(look) end end

local function BuildSquare()
	anchor = CreateFrame("Frame", "VoidShieldLiteAnchor", UIParent)
	anchor:SetSize(SIZE, SIZE)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	sq = CreateFrame("Frame", "VoidShieldLiteSquare", anchor)
	sq:SetSize(SIZE, SIZE)
	sq:SetPoint("CENTER")
	sq:SetFrameStrata("HIGH")
	sq:Hide()
	-- layers, back to front (the game's own number in instances sits above all of them)
	local base = sq:GetFrameLevel()
	local function Layer(offset)
		local f = CreateFrame("Frame", nil, sq)
		f:SetAllPoints()
		f:SetFrameLevel(base + offset)
		return f
	end
	sq.back, sq.art, sq.front, sq.top = Layer(1), Layer(3), Layer(5), Layer(7)
	BuildArt()
	-- the stack number sits on the box's left edge, with a soft dark patch behind it to read well
	sq.numBack = sq.top:CreateTexture(nil, "BACKGROUND")
	sq.numBack:SetTexture(M .. "glow") sq.numBack:SetVertexColor(0, 0, 0)
	sq.numBack:SetSize(0.95 * SIZE, 0.78 * SIZE)
	sq.numBack:SetPoint("CENTER", sq, "LEFT", -0.2 * SIZE, 0)
	sq.count = sq.top:CreateFontString(nil, "OVERLAY")
	sq.count:SetFont(FONT, NUM_SIZE, "THICKOUTLINE")
	sq.count:SetPoint("RIGHT", sq, "LEFT", NUM_X, 0)
	sq.count:SetTextColor(1, 0.9, 0.4)
	sq.drag = sq.top:CreateTexture(nil, "OVERLAY", nil, 7)
	sq.drag:SetAllPoints() sq.drag:SetTexture(M .. "boxmask") sq.drag:SetVertexColor(0.7, 0.4, 1)
	sq.drag:SetAlpha(0.35) sq.drag:Hide()
	sq:RegisterForDrag("LeftButton")
	sq:SetScript("OnDragStart", function() anchor:StartMoving() end)
	sq:SetScript("OnDragStop", function()
		anchor:StopMovingOrSizing()
		local p, _, rp, x, y = anchor:GetPoint()
		db.point, db.relPoint, db.x, db.y = p, rp, x, y
	end)
	sq:SetScript("OnMouseWheel", function(_, d) if IsControlKeyDown() then ns:SetScale(db.scale + d * 0.05) end end)
end
function ns:ApplyPosition()
	anchor:ClearAllPoints()
	anchor:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
	anchor:SetScale(db.scale)
end
function ns:SetScale(v)
	v = max(0.5, min(4, floor(v * 100 + 0.5) / 100))
	db.x, db.y = db.x * db.scale / v, db.y * db.scale / v
	db.scale = v
	ns:ApplyPosition()
end

---------------------------------------------------------------------------
-- Update: work out (proc? stacks?) and only redraw / play when something changed
---------------------------------------------------------------------------
local level, shownKey = 0, nil            -- level: 0 nothing, 1 proc + threshold, 2 proc + max
local lastWW, lastVS = -1, -1

function Update()
	if not sq then return end
	local now = GetTime()
	local ww, vs, how = nil, nil, nil
	if ns.test then
		ww, vs, how = ns.test.ww, ns.test.vs, "test"
	else
		local hidden = Hidden()
		if not hidden then Learn() end
		local rw, rv = Read(B.ww), Read(B.vs)
		local prevExact = exact.ww
		exact.ww = (rw ~= nil and not hidden) and rw or nil
		if chan and chan.gains and exact.ww and prevExact and exact.ww > prevExact then
			local f = (now - chan.start) / chan.dur
			for i = prevExact + 1, exact.ww do chan.gains[#chan.gains + 1] = min(1, max(0, f)) end
		end
		exact.vs = (rv ~= nil and not hidden) and rv or nil
		if est.wwExp <= now then est.ww = 0 end
		if est.vsExp <= now then est.vs = 0 end
		-- Weal and Woe
		if rw ~= nil and (rw > 0 or not hidden) then
			ww = rw est.ww, est.wwExp = rw, rw > 0 and (now + WW_DURATION) or 0
		else
			local band = WWBand()
			if band == 0 then ww = min(est.ww, db.threshold - 1)
			elseif band and band >= MAX then ww = MAX
			elseif band then ww = max(db.threshold, min(est.ww, MAX - 1))
			else ww = est.ww end
			est.ww = ww
		end
		-- Void Shield proc
		local button = ShieldIsVoid()
		if rv ~= nil and (rv > 0 or not hidden) then
			vs = rv est.vs, est.vsExp = rv, rv > 0 and (now + VS_DURATION) or 0
			-- check that the shield button agrees with the buff, so we know we can rely on it inside
			if rv > 0 and button == true then db.buttonWorks = true end
			if rv == 0 and button == false and db.buttonWorks == nil then db.buttonWorks = true end
		elseif button == true then
			vs = max(1, est.vs) est.vs, est.vsExp = vs, now + VS_DURATION
			how = "shield button"
		elseif button == false and db.buttonWorks then
			vs = 0 est.vs, est.vsExp = 0, 0
		else
			local present = VSPresent()
			if present == false then vs = 0 est.vs = 0
			elseif present == true then vs = max(1, est.vs) est.vs = vs
			else vs = est.vs end
		end
		how = how or (hidden and "hidden: estimate" or "exact")
	end
	if ww ~= lastWW or vs ~= lastVS then
		Debug(("Weal and Woe %d, Void Shield proc %s (%s)"):format(ww, vs > 0 and ("x" .. vs) or "none", how))
		lastWW, lastVS = ww, vs
	end

	local newLevel = 0
	if vs > 0 and ww >= MAX then newLevel = 2 elseif vs > 0 and ww >= db.threshold then newLevel = 1 end
	if newLevel > level then
		if newLevel == 2 and db.maxSound then Play("max") else Play("ready") end
		Debug(newLevel == 2 and "SOUND: max (proc + 10 stacks)" or ("SOUND: chime (proc + " .. db.threshold .. "+ stacks)"))
	end
	level = newLevel

	local show = ns.unlocked or level > 0
	-- inside instances, the game itself writes her real count into the square (exact), as long
	-- as the buff's spell ID is confirmed; otherwise our own count is shown
	local gameNumber = show and not ns.test and not ns.unlocked and engineParent and engineParent:IsShown()
		and (probe.wwProven or db.wwBuffID ~= nil)
	if engineParent then
		local a = gameNumber and 1 or 0
		if engineParent:GetAlpha() ~= a then engineParent:SetAlpha(a) end
	end
	local want = show and (level == 2 and 2 or 1) or 0
	if want ~= look then SetLook(want) end
	local key = show and (ww .. ":" .. level .. ":" .. tostring(gameNumber)) or nil
	if key == shownKey then return end
	shownKey = key
	if show then
		sq.count:SetText(gameNumber and "" or tostring((ns.unlocked and level == 0) and db.threshold or ww))
	end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local E = CreateFrame("Frame")
E:RegisterEvent("ADDON_LOADED")
E:RegisterEvent("PLAYER_LOGIN")
E:RegisterEvent("PLAYER_REGEN_ENABLED")
E:RegisterEvent("TRAIT_CONFIG_UPDATED")
E:RegisterEvent("ACTIVE_COMBAT_CONFIG_CHANGED")
E:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
E:RegisterUnitEvent("UNIT_AURA", "player")
E:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
E:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
E:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
E:SetScript("OnEvent", function(_, ev, a1, _, spellID)
	if ev == "ADDON_LOADED" then
		if a1 ~= ADDON then return end
		VoidShieldVortexDB = VoidShieldVortexDB or {}
		db = VoidShieldVortexDB
		if not db.proc7 then                  -- this version: fresh settings (keeps position)
			local keep = { point = db.point, relPoint = db.relPoint, x = db.x, y = db.y, scale = db.scale }
			for k in pairs(db) do db[k] = nil end
			for k, v in pairs(keep) do db[k] = v end
			db.proc7 = true
		end
		if not db.v52 then db.bolts, db.radianceBolts, db.boltSamples, db.v52 = nil, nil, nil, true end
		if not db.v55 then                   -- counts measured out of combat could be off: back to 7
			for _, b in pairs(db.builds or {}) do if not b.locked then b.bolts, b.samples = nil, nil end end
			db.v55 = true
		end
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
		return
	end
	if not db then return end
	if ev == "PLAYER_LOGIN" then
		buildKey = BuildKey()
		if db.bolts and not BuildData().bolts then
			BuildData().bolts, BuildData().locked = db.bolts, db.boltsLocked
		end
		db.bolts, db.boltsLocked, db.boltSamples = nil, nil, nil
		FindIDs()
		BuildSquare()
		ns:ApplyPosition()
		BuildEngine()
		C_Timer.NewTicker(0.2, function()
			if ns.engineDirty and not InCombatLockdown() then BuildEngine() end
			if engineParent then
				local want = Hidden()
				if want ~= engineParent:IsShown() then engineParent:SetShown(want) end
			end
			Update()
		end)
		Print(("shield + chime when you have a Void Shield proc and %d+ Weal and Woe; a phoenix at 10. |cffffd27f/vsv test|r to try it, |cffffd27f/vsv pack|r for sound packs."):format(db.threshold))
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("WealWoeAlert")
		if loaded then Print("Weal & Woe Alert is also on and makes its own sounds. Disable it (or /ww sound) so you only hear this one.") end
	elseif ev == "PLAYER_REGEN_ENABLED" then
		if ns.engineDirty then BuildEngine() end
	elseif ev == "TRAIT_CONFIG_UPDATED" or ev == "ACTIVE_COMBAT_CONFIG_CHANGED" or ev == "PLAYER_SPECIALIZATION_CHANGED" then
		C_Timer.After(0.5, function() RefreshBuild(true) end)
	elseif ev == "UNIT_AURA" then
		Update()
	elseif ev == "UNIT_SPELLCAST_CHANNEL_START" then
		if IsCast("penance", spellID) then PenanceStart(false)
		elseif IsCast("ultimate", spellID) then PenanceStart(true) end
	elseif ev == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if IsCast("penance", spellID) or IsCast("ultimate", spellID) then PenanceStop() Update() end
	elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
		local now = GetTime()
		if IsCast("shield", spellID) then
			-- the shield eats all Weal and Woe; a Void Shield uses up one proc. Void Shield lands on
			-- three allies and can report itself more than once: count one cast per 0.8 sec.
			est.ww, est.wwExp = 0, 0
			if now - (ns.lastShield or 0) > 0.8 then
				ns.lastShield = now
				if est.vs > 0 then est.vs = est.vs - 1 if est.vs == 0 then est.vsExp = 0 end end
				Debug(("shield cast: Weal and Woe used up, Void Shield procs left: ~%d"):format(est.vs))
			end
		elseif IsCast("penance", spellID) then
			PenanceStart(false)
		elseif IsCast("mindblast", spellID) then
			est.vs = min(VS_MAX, (est.vsExp > now and est.vs or 0) + 1)
			est.vsExp = now + VS_DURATION
			Debug("Mind Blast: Void Shield proc")
		end
		Update()
	end
end)

---------------------------------------------------------------------------
-- /vsv
---------------------------------------------------------------------------
SLASH_VOIDSHIELDLITE1, SLASH_VOIDSHIELDLITE2 = "/vsv", "/voidshield"
SlashCmdList.VOIDSHIELDLITE = function(msg)
	local cmd, a = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
	local num = tonumber(cmd)
	if num then
		if num >= 3 and num <= MAX then
			db.threshold = floor(num) ns.engineDirty = true shownKey = "redraw"
			Print(("square + chime at a Void Shield proc and %d+ stacks"):format(db.threshold))
		else Print("pick a number from 3 to 10") end
	elseif cmd == "test" then
		Print("test: 7 stacks without a proc (nothing), Mind Blast proc (chime), Penance to 10 (phoenix!), then your shield")
		-- each step: stacks, proc, how long it lasts (the 10-stack phoenix gets a good look)
		local steps = { { ww = 7, vs = 0, t = 2 }, { ww = 7, vs = 1, t = 2.5 }, { ww = 10, vs = 1, t = 6 }, { ww = 0, vs = 0, t = 0.5 } }
		local at = 0
		for _, s in ipairs(steps) do C_Timer.After(at, function() ns.test = s Update() end) at = at + s.t end
		C_Timer.After(at, function() ns.test = nil Update() end)
	elseif cmd == "pack" or cmd == "sounds" then
		local want = PACK_ALIASES[a] or a
		local pick
		for i, p in ipairs(PACKS) do
			if want == p.key or want == p.name:lower() or tonumber(want) == i then pick = p end
		end
		if not pick then
			Print("sound packs (|cffffd27f/vsv pack 2|r picks one and plays it for you):")
			for i, p in ipairs(PACKS) do
				Print(("  %d. %s%s - %s"):format(i, p.name, p == Pack() and " |cff7fff7f(on)|r" or "", p.about))
			end
		else
			db.pack = pick.key
			Print(("sound pack: %s. Here's the %d-stack sound, then the 10-stack one%s"):format(pick.name, db.threshold,
				db.sound and "" or " (your sounds are off: /vsv sound turns them on)"))
			PlayFile(pick.ready)
			C_Timer.After(2.2, function() PlayFile(pick.max, true) end)
		end
	elseif cmd == "fx" then
		db.fx = not db.fx
		ns:RefreshLook()
		Print("10-stack phoenix effects (wings, flames, lightning, sparks) " .. (db.fx and "ON" or "OFF: the square just turns gold, with a still glow"))
	elseif cmd == "unlock" then
		ns.unlocked = true sq:EnableMouse(true) sq:EnableMouseWheel(true) sq.drag:Show() shownKey = "redraw" Update()
		Print("drag the square where you want it (Ctrl + mouse wheel resizes), then /vsv lock")
	elseif cmd == "lock" then
		ns.unlocked = false sq:EnableMouse(false) sq:EnableMouseWheel(false) sq.drag:Hide() shownKey = "redraw" Update()
		Print("locked")
	elseif cmd == "scale" or cmd == "size" then
		local sign, step = a:match("^([%+%-])(%d*%.?%d*)$")      -- "+", "-", "+0.2", "-0.05"
		if sign then
			local d = tonumber(step) or 0.1
			ns:SetScale(db.scale + (sign == "+" and d or -d)) Print("size " .. db.scale)
		elseif tonumber(a) then
			ns:SetScale(tonumber(a)) Print("size " .. db.scale)
		else
			Print(("size %s (0.5 to 4). /vsv scale 1.1 sets it, /vsv scale + or - steps it by 0.1; Ctrl + mouse wheel works while unlocked"):format(db.scale))
		end
	elseif cmd == "sound" then
		db.sound = not db.sound Print("sounds " .. (db.sound and "ON" or "OFF"))
	elseif cmd == "max" then
		db.maxSound = not db.maxSound Print("bigger sound at 10 stacks: " .. (db.maxSound and "ON" or "OFF (the normal chime plays instead)"))
	elseif cmd == "stacks" and (tonumber(a) or a == "auto") then
		local b = BuildData()
		if a == "auto" then
			b.locked, b.samples = nil, nil
			Print("stacks per Penance for this talent build: measured automatically again")
		else
			b.bolts, b.locked = max(1, min(10, floor(tonumber(a)))), true
			Print(("one Penance gives %d stacks with this talent build (/vsv stacks auto to measure it instead)"):format(b.bolts))
		end
	elseif cmd == "debug" then
		db.debug = not db.debug Print("debug " .. (db.debug and "ON: every change is printed" or "OFF"))
	elseif cmd == "reset" then
		db.point, db.relPoint, db.x, db.y, db.scale = "CENTER", "CENTER", 0, -120, 1
		ns:ApplyPosition() Print("position reset")
	elseif cmd == "status" then
		Print("Weal and Woe IDs: " .. (#B.ww.ids > 0 and table.concat(B.ww.ids, ", ") or "none") .. (db.wwBuffID and " (confirmed)" or ""))
		Print("Void Shield proc IDs: " .. (#B.vs.ids > 0 and table.concat(B.vs.ids, ", ") or "none") .. (db.vsBuffID and " (confirmed)" or ""))
		local b = BuildData()
		local nb = 0 for _ in pairs(db.builds or {}) do nb = nb + 1 end
		Print(("buffs hidden right now: %s; this talent build: one Penance = %d stacks %s, bolt timing %s (%d build%s remembered)"):format(tostring(Hidden()),
			StacksPerPenance(), b.locked and "(set by you)" or (b.bolts and "(measured)" or "(default)"),
			b.timing and "measured" or "evenly spread", nb, nb == 1 and "" or "s"))
		Print(probe.wwProven and "in instances the sounds follow your buff exactly (the game's own number)"
			or "in instances the sounds are timed from your Penance bolts (the game hasn't let it read your buff yet)")
		local b = ShieldIsVoid()
		Print(("Void Shield proc from your shield button: %s%s"):format(b == nil and "can't read it" or (b and "proc up" or "no proc"),
			db.buttonWorks and " (checked: reliable)" or " (not checked yet)"))
		Print(("in instances, reading the game's own frames: Weal and Woe %s, Void Shield %s"):format(
			probe.wwProven and "yes (exact)" or "not yet", probe.vsProven and "yes (exact)" or "not yet"))
		Print(("sound pack: %s (/vsv pack), sounds %s; 10-stack phoenix effects %s (/vsv fx)"):format(
			Pack().name, db.sound and "on" or "off", db.fx and "on" or "off"))
	else
		Print("/vsv test - try it      /vsv 7 - chime at a proc + 7+ stacks (3-10)")
		Print("/vsv unlock - move it (Ctrl + wheel resizes), /vsv lock      /vsv scale 1.1 (or + / -)")
		Print("/vsv pack - sound packs: chimes, birdsong, ocean      /vsv fx - 10-stack phoenix effects on/off")
		Print("/vsv sound | max | stacks 7 (per Penance, this talent build) | status | debug | reset")
	end
end

function VoidShieldVortex_OnAddonCompartmentClick() SlashCmdList.VOIDSHIELDLITE("") end
