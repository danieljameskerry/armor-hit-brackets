--
-- Please see the LICENSE.md file included with this distribution for attribution and copyright information.
--

--	luacheck: globals getWeaponName
function getWeaponName(s)
	local sWeaponName = s:gsub('%[ATTACK %(%u%)%]', '');
	sWeaponName = sWeaponName:gsub('%[ATTACK #%d+ %(%u%)%]', '');
	sWeaponName = sWeaponName:gsub('%[%u+%]', '');
	if sWeaponName:match('%[USING ') then sWeaponName = sWeaponName:match('%[USING (.-)%]'); end
	sWeaponName = sWeaponName:gsub('%[.+%]', '');
	sWeaponName = sWeaponName:gsub(' %(vs%. .+%)', '');
	sWeaponName = StringManager.trim(sWeaponName);

	return sWeaponName or ''
end

local sRuleset;

local function onAttack_AHB(rSource, rTarget, rRoll) -- luacheck: ignore
	ArmorBracketManager.clearGlancingState(rSource);
	ActionsManager2.decodeAdvantage(rRoll);

	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);
	rMessage.text = string.gsub(rMessage.text, ' %[MOD:[^]]*%]', '');

	local rAction = {};
	rAction.nTotal = ActionsManager.total(rRoll);
	rAction.aMessages = {};

	local nDefenseVal, nAtkEffectsBonus, nDefEffectsBonus = ActorManager5E.getDefenseValue(rSource, rTarget, rRoll);
	if nAtkEffectsBonus ~= 0 then
		rAction.nTotal = rAction.nTotal + nAtkEffectsBonus;
		local sFormat = '[' .. Interface.getString('effects_tag') .. ' %+d]'
		table.insert(rAction.aMessages, string.format(sFormat, nAtkEffectsBonus));
	end
	if nDefEffectsBonus ~= 0 then
		nDefenseVal = nDefenseVal + nDefEffectsBonus;
		local sFormat = '[' .. Interface.getString('effects_def_tag') .. ' %+d]'
		table.insert(rAction.aMessages, string.format(sFormat, nDefEffectsBonus));
	end

	local sCritThreshold = string.match(rRoll.sDesc, '%[CRIT (%d+)%]');
	local nCritThreshold = tonumber(sCritThreshold) or 20;
	if nCritThreshold < 2 or nCritThreshold > 20 then nCritThreshold = 20; end

	-- ARMOR BRACKET DETECTION
	local sNodeTargetType, nodeTarget = ActorManager.getTypeAndNode(rTarget);
	local nArmorBracket = 0;
	if sNodeTargetType == "pc" then
		local sDexBonus = DB.getValue(nodeTarget, "defenses.ac.dexbonus", "");
		if sDexBonus == "" then
			if DB.getValue(nodeTarget, "defenses.ac.armor", 0) == 0 then
				--none
			else
				--light
				nArmorBracket = 1;
			end
		elseif sDexBonus:match("max") then
			--medium
			nArmorBracket = 2;
		elseif sDexBonus == "no" then
			--heavy
			nArmorBracket = 3;
		end
	else
		local sACText = DB.getValue(nodeTarget, "actext", "");
		--parse this text to work out armor type
		if sACText == "" then
			--none
		elseif sACText:match("natural armor") then
			--Subtract 10+DEX, type according to armor AC
			local nArmorAC = DB.getValue(nodeTarget, "ac", 0) - 10 - math.floor((DB.getValue(nodeTarget, "abilities.dexterity.score", 0) - 10) / 2);
			if nArmorAC < 4 then
				--light
				nArmorBracket = 1;
			elseif nArmorAC < 7 then
				--medium
				nArmorBracket = 2;
			elseif nArmorAC < 10 then
				--heavy
				nArmorBracket = 3;
			else
				--superheavy
				nArmorBracket = 4;
			end
		else
			local tArmors = {
			"padded","leather armor","studded leather",
			"hide armor","chain shirt","scale mail","breastplate","half plate",
			"ring mail","chain mail","splint","plate"};
			sACText = (sACText:match("(.+),") or sACText:sub(1, -2)):sub(2);
			for i,v in pairs(tArmors) do
				if sACText == v then
					if i < 4 then
						--light
						nArmorBracket = 1;
					elseif i < 9 then
						--medium
						nArmorBracket = 2;
					else
						--heavy
						nArmorBracket = 3;
					end
				end
			end
		end
	end
	--	calculate how much attacks hit/miss by to check which bracket it's in
	local nHitMargin = 0;
	if nDefenseVal then
		if (rAction.nTotal - nDefenseVal) > 0 then
			nHitMargin = rAction.nTotal - nDefenseVal
		elseif (rAction.nTotal - nDefenseVal) < 0 then
			nHitMargin = nDefenseVal - rAction.nTotal
		end
	end
	-- END ARMOR BRACKET DETECTION

	rAction.nFirstDie = 0;
	if #(rRoll.aDice) > 0 then rAction.nFirstDie = rRoll.aDice[1].result or 0; end
	if rAction.nFirstDie >= nCritThreshold then
		rAction.bSpecial = true;
		rAction.sResult = 'crit';
		table.insert(rAction.aMessages, '[CRITICAL HIT]');
	elseif rAction.nFirstDie == 1 then
		rAction.sResult = 'fumble';
		table.insert(rAction.aMessages, '[AUTOMATIC MISS]');
	elseif nDefenseVal then
		if rAction.nTotal >= nDefenseVal then
			--ARMOR BRACKETS - check for glance
			if nHitMargin < nArmorBracket then
				rAction.sResult = 'glance';
				table.insert(rAction.aMessages, '[GLANCING HIT]');
			else
				rAction.sResult = 'hit';
				table.insert(rAction.aMessages, '[HIT]');
			end
		else
			--ARMOR BRACKETS - check for glance
			if nHitMargin <= nArmorBracket then
				rAction.sResult = 'glance';
				table.insert(rAction.aMessages, '[GLANCING MISS]');
			else
				-- could check between dodge, deflect or miss? Would still need to include MISS on the result table for parsing
				rAction.sResult = 'miss';
				table.insert(rAction.aMessages, '[MISS]');
			end
		end
	end

	--	bmos adding weapon name to chat
	--	for compatibility with ammunition tracker, add this here in your onAttack function
	if ArmorBracketManager and OptionsManager.isOption('ATKRESULTWEAPON', 'on') then
		table.insert(rAction.aMessages, 'with ' .. ArmorBracketManager.getWeaponName(rRoll.sDesc))
	end

	if not rTarget then rMessage.text = rMessage.text .. ' ' .. table.concat(rAction.aMessages, ' '); end

	Comm.deliverChatMessage(rMessage);

	if rTarget then
		ActionAttack.notifyApplyAttack(
						rSource, rTarget, rRoll.bTower, rRoll.sType, rRoll.sDesc, rAction.nTotal, table.concat(rAction.aMessages, ' ')
		);
	end

	-- TRACK CRITICAL STATE
	if rAction.sResult == 'crit' then ActionAttack.setCritState(rSource, rTarget); end
	
	--ARMOR BRACKETS - TRACK GLANCING STATE
	if rAction.sResult == 'glance' then ArmorBracketManager.setGlancingState(rSource, rTarget); end

	-- REMOVE TARGET ON MISS OPTION
	if rTarget then
		if (rAction.sResult == 'miss' or rAction.sResult == 'fumble') then
			if rRoll.bRemoveOnMiss then TargetingManager.removeTarget(ActorManager.getCTNodeName(rSource), ActorManager.getCTNodeName(rTarget)); end
		end
	end

	-- HANDLE FUMBLE/CRIT HOUSE RULES
	local sOptionHRFC = OptionsManager.getOption('HRFC');
	if rAction.sResult == 'fumble' and ((sOptionHRFC == 'both') or (sOptionHRFC == 'fumble')) then ActionAttack.notifyApplyHRFC('Fumble'); end
	if rAction.sResult == 'crit' and ((sOptionHRFC == 'both') or (sOptionHRFC == 'criticalhit')) then
		ActionAttack.notifyApplyHRFC('Critical Hit');
	end
end

aGlanceState = {};

function setGlancingState(rSource, rTarget)
	local sSourceCT = ActorManager.getCreatureNodeName(rSource);
	if sSourceCT == "" then
		return;
	end
	local sTargetCT = "";
	if rTarget then
		sTargetCT = ActorManager.getCTNodeName(rTarget);
	end
	
	if not aGlanceState[sSourceCT] then
		aGlanceState[sSourceCT] = {};
	end
	table.insert(aGlanceState[sSourceCT], sTargetCT);
end

function clearGlancingState(rSource)
	local sSourceCT = ActorManager.getCreatureNodeName(rSource);
	if sSourceCT ~= "" then
		aGlanceState[sSourceCT] = nil;
	end
end

function isGlancing(rSource, rTarget)
	local sSourceCT = ActorManager.getCreatureNodeName(rSource);
	if sSourceCT == "" then
		return;
	end
	local sTargetCT = "";
	if rTarget then
		sTargetCT = ActorManager.getCTNodeName(rTarget);
	end

	if not aGlanceState[sSourceCT] then
		return false;
	end
	
	for k,v in ipairs(aGlanceState[sSourceCT]) do
		if v == sTargetCT then
			return true;
		end
	end
	
	return false;
end

function getExpiringEffects(rActor, aEffectType, bAddEmptyBonus, aFilter, rFilterActor)
	if not rActor or not aEffectType then
		return {}, 0;
	end
	
	-- MAKE BONUS TYPE INTO TABLE, IF NEEDED
	if type(aEffectType) ~= "table" then
		aEffectType = { aEffectType };
	end
	
	-- PER EFFECT TYPE VARIABLES
	local results = {};
	local bonuses = {};
	local penalties = {};
	local nEffectCount = 0;
	
	for k, v in pairs(aEffectType) do
		--ARMOR HIT BRACKETS - FIND EXPIRING EFFECTS
		local aEffectsByType = {};
		--loop through every effect 
		for _,v in pairs(DB.getChildren(ActorManager.getCTNode(rActor), "effects")) do
			--only proceed if effect is active
			if (DB.getValue(v, "isactive", 0) ~= 0) then
				--check that effect will be applied to target
				if not EffectManager.isTargetedEffect(v) or EffectManager.isEffectTarget(v, rFilterActor) then
					--check if effect will expire on next action / roll / use
					local sApply = DB.getValue(v, "apply", "");
					if sApply == "action" or sApply == "roll" or sApply == "single" then
						--perform parsing to split effect into its components so they can be compared later
						local aEffectComps = EffectManager.parseEffect(DB.getValue(v, "label", ""));
						for kEffectComp,sEffectComp in ipairs(aEffectComps) do
							local rEffectComp = EffectManager5E.parseEffectComp(sEffectComp);
							if rEffectComp.type == "IF" then
								if not EffectManager5E.checkConditional(rActor, v, rEffectComp.remainder) then
									break;
								end
							elseif rEffectComp.type == "IFT" then
								if not rFilterActor then
									break;
								end
								if not EffectManager5E.checkConditional(rFilterActor, v, rEffectComp.remainder, rActor) then
									break;
								end
							end
							table.insert(aEffectsByType, rEffectComp);
						end
					end
				end
			end
		end

		-- ITERATE THROUGH EFFECTS THAT MATCHED
		for k2,v2 in pairs(aEffectsByType) do
			-- LOOK FOR ENERGY OR BONUS TYPES
			local dmg_type = nil;
			local mod_type = nil;
			for _,v3 in pairs(v2.remainder) do
				if StringManager.contains(DataCommon.dmgtypes, v3) or StringManager.contains(DataCommon.conditions, v3) or v3 == "all" then
					dmg_type = v3;
					break;
				elseif StringManager.contains(DataCommon.bonustypes, v3) then
					mod_type = v3;
					break;
				end
			end
			
			-- IF MODIFIER TYPE IS UNTYPED, THEN APPEND MODIFIERS
			-- (SUPPORTS DICE)
			if dmg_type or not mod_type then
				-- ADD EFFECT RESULTS 
				local new_key = dmg_type or "";
				local new_results = results[new_key] or {dice = {}, mod = 0, remainder = {}};

				-- BUILD THE NEW RESULT
				for _,v3 in pairs(v2.dice) do
					table.insert(new_results.dice, v3); 
				end
				if bAddEmptyBonus then
					new_results.mod = new_results.mod + v2.mod;
				else
					new_results.mod = math.max(new_results.mod, v2.mod);
				end
				for _,v3 in pairs(v2.remainder) do
					table.insert(new_results.remainder, v3);
				end

				-- SET THE NEW DICE RESULTS BASED ON ENERGY TYPE
				results[new_key] = new_results;

			-- OTHERWISE, TRACK BONUSES AND PENALTIES BY MODIFIER TYPE 
			-- (IGNORE DICE, ONLY TAKE BIGGEST BONUS AND/OR PENALTY FOR EACH MODIFIER TYPE)
			else
				local bStackable = StringManager.contains(DataCommon.stackablebonustypes, mod_type);
				if v2.mod >= 0 then
					if bStackable then
						bonuses[mod_type] = (bonuses[mod_type] or 0) + v2.mod;
					else
						bonuses[mod_type] = math.max(v2.mod, bonuses[mod_type] or 0);
					end
				elseif v2.mod < 0 then
					if bStackable then
						penalties[mod_type] = (penalties[mod_type] or 0) + v2.mod;
					else
						penalties[mod_type] = math.min(v2.mod, penalties[mod_type] or 0);
					end
				end

			end
			
			-- INCREMENT EFFECT COUNT
			nEffectCount = nEffectCount + 1;
		end
	end

	-- COMBINE BONUSES AND PENALTIES FOR NON-ENERGY TYPED MODIFIERS
	for k2,v2 in pairs(bonuses) do
		if results[k2] then
			results[k2].mod = results[k2].mod + v2;
		else
			results[k2] = {dice = {}, mod = v2, remainder = {}};
		end
	end
	for k2,v2 in pairs(penalties) do
		if results[k2] then
			results[k2].mod = results[k2].mod + v2;
		else
			results[k2] = {dice = {}, mod = v2, remainder = {}};
		end
	end

	return results, nEffectCount;
end

function applyDmgEffectsToModRoll_AHB(rRoll, rSource, rTarget)
	
	local aExpiringEffects, nExpiringEffects = ArmorBracketManager.getExpiringEffects(rSource, "DMG", true, rRoll.tAttackFilter, rTarget);
	--Debug.chat("EXPIRING EFFECTS:",aExpiringEffects)
	local tDmgEffects, nDmgEffects = EffectManager5E.getEffectsBonusByType(rSource, "DMG", true, rRoll.tAttackFilter, rTarget);
	--Debug.chat("ALL DAMAGE EFFECTS",tDmgEffects)
	if nDmgEffects > 0 then
		local sEffectBaseType = "";
		if #(rRoll.clauses) > 0 then
			sEffectBaseType = rRoll.clauses[1].dmgtype or "";
		end
		
		for _,v in pairs(tDmgEffects) do
			local bCritEffect = false;
			local aEffectDmgType = {};
			local aEffectSpecialDmgType = {};
			for _,sType in ipairs(v.remainder) do
				if StringManager.contains(DataCommon.specialdmgtypes, sType) then
					table.insert(aEffectSpecialDmgType, sType);
					if sType == "critical" then
						bCritEffect = true;
					end
				elseif StringManager.contains(DataCommon.dmgtypes, sType) then
					table.insert(aEffectDmgType, sType);
				end
			end
			
			if not bCritEffect or rRoll.bCritical then
				rRoll.bEffects = true;
		
				local rClause = {};
				
				rClause.dice = {};
				for _,vDie in ipairs(v.dice) do
					table.insert(rRoll.tEffectDice, vDie);
					table.insert(rClause.dice, vDie);
					if rClause.reroll then
						table.insert(rClause.reroll, 0);
					end
					if vDie:sub(1,1) == "-" then
						table.insert(rRoll.aDice, "-p" .. vDie:sub(3));
					else
						table.insert(rRoll.aDice, "p" .. vDie:sub(2));
					end
				end

				rRoll.nEffectMod = rRoll.nEffectMod + v.mod;
				rClause.modifier = v.mod;
				rRoll.nMod = rRoll.nMod + v.mod;
				
				rClause.stat = "";

				if #aEffectDmgType == 0 then
					table.insert(aEffectDmgType, sEffectBaseType);
				end
				for _,vSpecialDmgType in ipairs(aEffectSpecialDmgType) do
					table.insert(aEffectDmgType, vSpecialDmgType);
				end
				
				--add special glanceimmune damage type if the effect will expire on use
				if ArmorBracketManager.isGlancing(rSource, rTarget) then
					for k2,v2 in pairs(aExpiringEffects) do
						--Debug.chat("1",v2)
						--Debug.chat("2",v)
						if ArmorBracketManager.tableToString(v) == ArmorBracketManager.tableToString(v2) then
							--Debug.chat("Found matching effects:", v)
							table.insert(aEffectDmgType, "glanceimmune");
						end
					end
				end
				
				rClause.dmgtype = table.concat(aEffectDmgType, ",");

				table.insert(rRoll.clauses, rClause);
			end
		end
	end
end

function getDamageAdjust_AHB(rSource, rTarget, nDamage, rDamageOutput)
	local nDamageAdjust = 0;
	local bVulnerable = false;
	local bResist = false;
	
	-- Get damage adjustment effects
	local aImmune = ActionDamage.getReductionType(rSource, rTarget, "IMMUNE");
	local aVuln = ActionDamage.getReductionType(rSource, rTarget, "VULN");
	local aResist = ActionDamage.getReductionType(rSource, rTarget, "RESIST");
	
	-- Handle immune all
	if aImmune["all"] then
		nDamageAdjust = 0 - nDamage;
		bResist = true;
		return nDamageAdjust, bVulnerable, bResist;
	end
	
	-- Iterate through damage type entries for vulnerability, resistance and immunity
	local nVulnApplied = 0;
	local bResistCarry = false;
	for k, v in pairs(rDamageOutput.aDamageTypes) do
		-- Get individual damage types for each damage clause
		local aSrcDmgClauseTypes = {};
		local aTemp = StringManager.split(k, ",", true);
		for _,vType in ipairs(aTemp) do
			if vType ~= "untyped" and vType ~= "" then
				table.insert(aSrcDmgClauseTypes, vType);
			end
		end
		--Debug.chat("DAMAGE CLAUSE TYPES",aSrcDmgClauseTypes)
		
		-- Handle standard immunity, vulnerability and resistance
		local bLocalVulnerable = ActionDamage.checkReductionType(aVuln, aSrcDmgClauseTypes);
		local bLocalResist = ActionDamage.checkReductionType(aResist, aSrcDmgClauseTypes);
		local bLocalImmune = ActionDamage.checkReductionType(aImmune, aSrcDmgClauseTypes);
		
		-- Calculate adjustment
		-- Vulnerability = double
		-- Resistance = half
		-- Immunity = none
		local nLocalDamageAdjust = 0;
		if bLocalImmune then
			nLocalDamageAdjust = -v;
			bResist = true;
		else
			-- Handle numerical resistance
			local nLocalResist = ActionDamage.checkNumericalReductionType(aResist, aSrcDmgClauseTypes, v);
			if nLocalResist ~= 0 then
				nLocalDamageAdjust = nLocalDamageAdjust - nLocalResist;
				bResist = true;
			end
			-- Handle numerical vulnerability
			local nLocalVulnerable = ActionDamage.checkNumericalReductionType(aVuln, aSrcDmgClauseTypes);
			if nLocalVulnerable ~= 0 then
				nLocalDamageAdjust = nLocalDamageAdjust + nLocalVulnerable;
				bVulnerable = true;
			end
			-- Handle standard resistance
			if bLocalResist then
				local nResistOddCheck = (nLocalDamageAdjust + v) % 2;
				local nAdj = math.ceil((nLocalDamageAdjust + v) / 2);
				nLocalDamageAdjust = nLocalDamageAdjust - nAdj;
				if nResistOddCheck == 1 then
					if bResistCarry then
						nLocalDamageAdjust = nLocalDamageAdjust + 1;
						bResistCarry = false;
					else
						bResistCarry = true;
					end
				end
				bResist = true;
			end
			-- Handle standard vulnerability
			if bLocalVulnerable then
				nLocalDamageAdjust = nLocalDamageAdjust + (nLocalDamageAdjust + v);
				bVulnerable = true;
			end
			-- ARMOR BRACKETS - HANDLE GLANCING DAMAGE
			if ArmorBracketManager.isGlancing(rSource, rTarget) then
				--Debug.chat("GLANCING, HALF DAMAGE")
				local bIsGlancing = true
				for _,sDmgType in pairs(aSrcDmgClauseTypes) do
					--Debug.chat("DAMAGE TYPE",sDmgType)
					if sDmgType == "glanceimmune" then
						bIsGlancing = false
						--Debug.chat("GLANCE IMMUNE")
					end
				end
				if bIsGlancing then
					nResistOddCheck = (nLocalDamageAdjust + v) % 2;
					nAdj = math.ceil((nLocalDamageAdjust + v) / 2);
					nLocalDamageAdjust = nLocalDamageAdjust - nAdj;
					if nResistOddCheck == 1 then
						if bResistCarry then
							nLocalDamageAdjust = nLocalDamageAdjust + 1;
							bResistCarry = false;
						else
							bResistCarry = true;
						end
					end
					--Debug.chat("HALVED DAMAGE")
				end
			end
		end
		
		-- Apply adjustment to this damage type clause
		nDamageAdjust = nDamageAdjust + nLocalDamageAdjust;
	end
	
	-- Handle damage threshold
	local nDTMod, nDTCount = EffectManager5E.getEffectsBonus(rTarget, {"DT"}, true);
	if nDTMod > 0 then
		if nDTMod > (nDamage + nDamageAdjust) then 
			nDamageAdjust = 0 - nDamage;
			bResist = true;
		end
	end

	-- Results + clear glancing
	ArmorBracketManager.clearGlancingState(rSource)
	return nDamageAdjust, bVulnerable, bResist;
end

function tableToString(tbl)
    local result = "{"
    for k, v in pairs(tbl) do
        -- Check the key type (ignore any numerical keys - assume its an array)
        if type(k) == "string" then
            result = result.."[\""..k.."\"]".."="
        end

        -- Check the value type
        if type(v) == "table" then
            result = result..ArmorBracketManager.tableToString(v)
        elseif type(v) == "boolean" then
            result = result..tostring(v)
        else
            result = result.."\""..v.."\""
        end
        result = result..","
    end
    -- Remove leading commas from the result
    if result ~= "{" then
        result = result:sub(1, result:len()-1)
    end
    return result.."}"
end

-- Function Overrides
function onInit()
	ActionsManager.unregisterResultHandler('attack');
	ActionsManager.registerResultHandler('attack', onAttack_AHB);
	ActionAttack.onAttack = onAttack_AHB;
	ActionDamage.applyDmgEffectsToModRoll = applyDmgEffectsToModRoll_AHB;
	ActionDamage.getDamageAdjust = getDamageAdjust_AHB;
	
	OptionsManager.registerOption2(
					'ATKRESULTWEAPON', false, 'option_header_game', 'opt_lab_atkresultweaponname', 'option_entry_cycler',
					{ labels = 'option_val_on', values = 'on', baselabel = 'option_val_off', baseval = 'off', default = 'off' }
	);
end
