local lpeg = require("lpeg")

local C, Cc, Cf, Cg, Ct, P, R, S = lpeg.C, lpeg.Cc, lpeg.Cf, lpeg.Cg, lpeg.Ct, lpeg.P, lpeg.R, lpeg.S

local function concat(a, b)
   return a .. b
end
local function split(s, sep)
   local psep = P(sep)
   local elem = C((1 - psep)^0)
   local p = Ct(elem * (psep * elem)^0)
   return p:match(s)
end

local SP = S" "
local TAB = S"\t"
local LF = P"\n"
local REST = (1 - LF)^0
local LINE = REST * LF
local INT = R"09"^1 / tonumber

local identifier = C((1 - S":")^0) * S":"

local sink_index = (P"    " + P"  * ") * P"index: " * INT * LF
local attr_ident = TAB * identifier * SP^1
local attr_value = Cf(C(REST) * (C(LF) * TAB * SP^1 * C(REST))^0 * LF, concat)
local attr = Cg(attr_ident * attr_value)
local attrs = Cf(Ct("") * attr^1, rawset)

local prop_header = TAB * "properties:" * LF
local prop_identifier = C((1 - S"= ")^0) * SP^0 * S"="
local prop_value = '"' * C((1 - S'"')^0) * '"'
local prop_line = Cg(TAB * TAB * prop_identifier * SP^0 * prop_value * LF)
local prop_lines = Cf(Ct("") * prop_line^1, rawset)

local ports = TAB * "ports:" * LF * (TAB * TAB * LINE)^1 * (TAB * "active port: " * LINE)^-1
local sinks = TAB * "sinks:" * LF * (TAB * TAB * LINE)^1
local sources = TAB * "sources:" * LF * (TAB * TAB * LINE)^1

local profile_header = TAB * "profiles:" * LF
local profile_ident = C((1 - P": ")^1) * ":"
local profile_name = C((1 - P" (priority")^1)
local profile_attrs = " (priority " * INT * REST
local profile_value = Cg(profile_name, "name") * Cg(profile_attrs, "priority")
local profile_line = Cg(TAB * TAB * profile_ident * SP^1 * Ct(profile_value) * LF)
local profile_lines = Cf(Ct("") * profile_line^1, rawset)
local profile_active = TAB * "active profile: <" * C((1 - S">")^1) * ">" * LF

local sink = Ct(Cg(sink_index, "index") *
                   Cg(attrs, "attr") *
                   prop_header *
                   Cg(prop_lines, "prop") *
                   ports^-1)

local list_sinks_parser = LINE * Ct(sink^0)


local card = Ct(Cg(sink_index, "index") *
                   Cg(attrs, "attr") *
                   prop_header *
                   Cg(prop_lines, "prop") *
                   profile_header *
                   Cg(profile_lines, "profile") *
                   Cg(profile_active, "active_profile") *
                   sinks^0 *
                   sources^0 *
                   ports^-1)

local list_cards_parser = LINE * Ct(card^0)

local info_line = identifier * SP^1 * C(REST) * LF
local info_parser = Cf(Ct("") * Cg(info_line)^1, rawset)

function parse_pacmd_list_sinks(data)
   return list_sinks_parser:match(data)
end

function parse_pacmd_list_cards(data)
   return list_cards_parser:match(data)
end

function parse_pactl_info(data)
   return info_parser:match(data)
end

function parse_pacmd_dump(lines)
   local line
   local ret = {
      ["default"] = nil,
      ["mute"] = {},
      ["profile"] = {},
      ["volume"] = {}
   }
   local funcs = {
      ["set-card-profile"] = function(card, profile)
         ret["profile"][card] = profile
      end,
      ["set-default-sink"] = function(sink)
         ret["default"] = sink
      end,
      ["set-sink-mute"] = function(sink, val)
         ret["mute"][sink] = val == "yes"
      end,
      ["set-sink-volume"] = function(sink, volume)
         ret["volume"][sink] = tonumber(volume) / 0x10000*100
      end
   }
   for line in lines do
      if string.len(line) > 0 then
         local tokens = split(line, " ")
         local func = funcs[tokens[1]]
         if func ~= nil then
            func(table.unpack(tokens, 2))
         end
      end
   end
   return ret
end

local parser = {
   parse_pacmd_list_sinks = parse_pacmd_list_sinks,
   parse_pacmd_list_cards = parse_pacmd_list_cards,
   parse_pactl_info = parse_pactl_info,
   parse_pacmd_dump = parse_pacmd_dump
}

return parser
