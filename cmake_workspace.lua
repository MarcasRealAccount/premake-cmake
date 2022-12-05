local p         = premake
local project   = p.project
local workspace = p.workspace
local tree      = p.tree
local cmake     = p.extensions.cmake
cmake.workspace = {}
local m         = cmake.workspace

m.languageToEnabledLanguage = {
	["C"]             = "C",
	["C++"]           = "CXX",
	["Objective-C"]   = "OBJC",
	["Objective-C++"] = "OBJCXX"
}

m.props = function(wks)
	return {
		m.minimumRequiredVersion,
		m.enableLanguages,
		m.buildTypes,
		m.defaultFlags,
		m.name,
		m.projects
	}
end

function cmake.generateWorkspace(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.generateWorkspace", { wks.name })
	p.indent("\t")
	p.utf8()
	
	wks.buildTypes = {}
	for cfg in workspace.eachconfig(wks) do
		table.insert(wks.buildTypes, cmake.common.configName(cfg, #wks.platforms > 1))
	end
	
	p.callArray(m.props, wks, buildTypes)
	timer.stop()
end

function m.minimumRequiredVersion(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.workspace.minimumRequiredVersion", { wks.name })
	p.w("cmake_minimum_required(VERSION 3.16)")
	timer.stop()
end

function m.enableLanguages(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.workspace.enableLanguages", { wks.name })
	local enabledLanguages = {}
	for prj in wks:eachproject() do
		local tr = prj:getsourcetree()
		for cfg in prj:eachconfig() do
			tr:traverse({
				onleaf = function(node, depth)
					if node.configs then
						local filecfg = node:getconfig(cfg)
						if filecfg.compileas then
							local lang = languageToEnabledLanguage[filecfg.compileas]
							if lang then
								enabledLanguages[lang] = true
							end
						end
					end
				end
			}, true)
		
			local setLang = cfg.language
			if setLang then
				local lang = languageToEnabledLanguage[setLang]
				if lang then
					enabledLanguages[lang] = true
				end
			end
		end
	end
	for lang, _ in pairs(enabledLanguages) do
		p.w("enable_language(%s)", lang)
	end
	timer.stop()
end

function m.buildTypes(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.workspace.buildTypes", { wks.name })
	p.w("set(PREMAKE_BUILD_TYPES \"%s\")", table.concat(wks.buildTypes, "\" \""))
	p.w("get_property(multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)")
	p.push("if(multi_config)")
	p.w("set(CMAKE_CONFIGURATION_TYPES \"${PREMAKE_BUILD_TYPES}\" CACHE STRING \"List of supported configuration types\" FORCE)")
	p.pop()
	p.push("else()")
	p.w("set(CMAKE_BUILD_TYPE \"%s\" CACHE STRING \"Build Type of the project.\")", wks.buildTypes[1])
	p.w("set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS \"${PREMAKE_BUILD_TYPES}\")")
	p.push("if(NOT CMAKE_BUILD_TYPE IN_LIST PREMAKE_BUILD_TYPES)")
	p.push("message(FATAL_ERROR")
	p.w("\"Invalid build type '${CMAKE_BUILD_TYPE}'.")
	p.w("CMAKE_BUILD_TYPE must be any of the possible values:")
	p.w("${PREMAKE_BUILD_TYPES}\"")
	p.pop(")")
	p.pop("endif()")
	p.pop("endif()")
	timer.stop()
end

function m.defaultFlags(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.workspace.defaultFlags", { wks.name })
	p.w("set(CMAKE_MSVC_RUNTIME_LIBRARY \"\")")
	p.w("set(CMAKE_C_FLAGS \"\")")
	p.w("set(CMAKE_CXX_FLAGS \"\")")
	for _, buildType in ipairs(wks.buildTypes) do
		p.w("set(CMAKE_C_FLAGS_%s \"\")", string.upper(buildType))
		p.w("set(CMAKE_CXX_FLAGS_%s \"\")", string.upper(buildType))
	end
	timer.stop()
end

function m.name(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.workspace.name", { wks.name })
	p.w("project(\"%s\")", wks.name)
	timer.stop()
end

function m.projects(wks)
	local timer = cmake.common.createTimer("p.extensions.cmake.workspace.projects", { wks.name })
	local tr = workspace.grouptree(wks)
	tree.traverse(tr, {
		onleaf = function(n)
			local prj = n.project
			if prj.kind == "Utility" then return end
			p.w("include(\"%s\")", path.getrelative(prj.workspace.location, p.filename(prj, ".cmake")))
		end
	})
	timer.stop()
end
