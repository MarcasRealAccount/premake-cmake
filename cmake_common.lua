local p         = premake
local project   = p.project
local workspace = p.workspace
local tree      = p.tree
local cmake     = p.extensions.cmake
cmake.common    = {}
local m         = cmake.common

m.cppStandards = {
	["C++98"]   = "98",
	["C++11"]   = "11",
	["C++14"]   = "14",
	["C++17"]   = "17",
	["C++20"]   = "20",
	["C++2a"]   = "20",
	["gnu++98"] = "98",
	["gnu++11"] = "11",
	["gnu++14"] = "14",
	["gnu++17"] = "17",
	["gnu++20"] = "20"
}

m.compileasLangs = {
	["C"]               = "C",
	["C++"]             = "CXX",
	["Objective-C"]     = "OBJC",
	["Objective-C++"]   = "OBJCXX"
}

function m.configName(config, includePlatform)
	if includePlatform then
		return config.platform .. "-" .. config.buildcfg
	else
		return config.buildcfg
	end
end

function m.getCompiler(cfg)
	local default = iif(cfg.system == p.WINDOWS, "msc", "clang")
	local toolset = p.tools[_OPTIONS.cc or cfg.toolset or default]
	if not toolset then
		error("Invalid toolset '" .. (_OPTIONS.cc or cfg.toolset) .. "'")
	end
	return toolset
end

function m.fixSingleQuotes(command)
	if type(command) == "table" then
		local result = {}
		for k, v in pairs(command) do
			result[k] = v:gsub("'(.-)'", "\"%1\"")
		end
		return result
	else
		return command:gsub("'(.-)'", "\"%1\"")
	end
end

function m.escapeStrings(str)
	return str:gsub("\"", "\\\"")
end

function m.isFramework(lib)
	return path.getextension(lib) == ".framework"
end

function m.getFrameworkName(framework)
	return string.sub(framework, 1, string.find(framework, "%.") - 1)
end
