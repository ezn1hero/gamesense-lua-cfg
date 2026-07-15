local ffi = require("ffi")
local clipboard = pcall(require, "gamesense/clipboard") and require("gamesense/clipboard") or nil

local DEFAULT_MODELS = {
    ["Ghostface"] = "models/player/custom_player/kaesar/ghostface/ghostface.mdl",
}

local DEFAULT_HITSOUNDS = {
    "hitsounds/ston_1.wav", "hitsounds/ston_2.wav", "hitsounds/ston_3.wav", "hitsounds/ston_4.wav"
}

local saved_models = database.read("demontool_models") or DEFAULT_MODELS
local saved_hitsounds = database.read("demontool_hitsounds") or DEFAULT_HITSOUNDS
local model_names = {}

local script_load_time = globals.realtime()
local splash_duration = 4.0 

ffi.cdef [[
    typedef void FILE;
    FILE* fopen(const char* filename, const char* mode);
    int fseek(FILE* stream, long offset, int origin);
    long ftell(FILE* stream);
    size_t fread(void* ptr, size_t size, size_t nmemb, FILE* stream);
    int fclose(FILE* stream);

    typedef struct {
    	void* fnHandle; char szName[260]; int nLoadFlags; int nServerCount;    
    	int type; int flags; float vecMins[3]; float vecMaxs[3]; float radius; char pad[0x1C];       
    } model_t;
    typedef int(__thiscall* get_model_index_t)(void*, const char*);
    typedef const model_t(__thiscall* find_or_load_model_t)(void*, const char*);
    typedef int(__thiscall* add_string_t)(void*, bool, const char*, int, const void*);
    typedef void*(__thiscall* find_table_t)(void*, const char*);
    typedef void(__thiscall* set_model_index_t)(void*, int);
    typedef void*(__thiscall* get_client_entity_t)(void*, int);
]]

local class_ptr = ffi.typeof("void***")
local ientitylist = ffi.cast(class_ptr, client.create_interface("client_panorama.dll", "VClientEntityList003") or error("VClientEntityList003 missing"))
local get_client_entity = ffi.cast("get_client_entity_t", ientitylist[0][3])

local ivmodelinfo = ffi.cast(class_ptr, client.create_interface("engine.dll", "VModelInfoClient004") or error("VModelInfoClient004 missing"))
local get_model_index = ffi.cast("get_model_index_t", ivmodelinfo[0][2])
local find_or_load_model = ffi.cast("find_or_load_model_t", ivmodelinfo[0][39])

local networkstringtablecontainer = ffi.cast(class_ptr, client.create_interface("engine.dll", "VEngineClientStringTable001") or error("VEngineClientStringTable001 missing"))
local find_table = ffi.cast("find_table_t", networkstringtablecontainer[0][3])

local function read_file_binary(filename)
    local paths = {
        "C:/Program Files (x86)/Steam/steamapps/common/csgo legacy/csgo/lua/demontool/" .. filename,
        "C:\\Program Files (x86)\\Steam\\steamapps\\common\\csgo legacy\\csgo\\lua\\demontool\\" .. filename,
        "csgo/lua/demontool/" .. filename,
        "lua/demontool/" .. filename,
        filename
    }
    
    for _, path in ipairs(paths) do
        local status, result = pcall(function()
            local file = ffi.C.fopen(path, "rb")
            if file == nil then return nil end
            
            ffi.C.fseek(file, 0, 2)
            local size = tonumber(ffi.C.ftell(file))
            ffi.C.fseek(file, 0, 0)
            
            if size > 0 then
                local buffer = ffi.new("char[?]", size)
                local read_bytes = ffi.C.fread(buffer, 1, size, file)
                ffi.C.fclose(file)
                client.log("[demontool] Файл изображения найден: " .. path)
                return ffi.string(buffer, tonumber(read_bytes))
            end
            ffi.C.fclose(file)
            return nil
        end)
        if status and result and #result > 0 then return result end
    end
    return nil
end

local splash_texture = nil
local raw_image_data = read_file_binary("girl.png")
if raw_image_data then
    pcall(function() splash_texture = renderer.load_png(raw_image_data) end)
end

local tab_list = {"Main", "Model changer", "Hitsounds", "Autobuy", "Configs Manager"}
local ui_tab = ui.new_combobox("LUA", "B", "Demontool menu tab", tab_list)

-- Main
local ui_watermark = ui.new_checkbox("LUA", "B", "Watermark")

-- Model Changer
local ui_model_enable = ui.new_checkbox("LUA", "B", "Enable model changer")
local ui_model_list = ui.new_listbox("LUA", "B", "Model list", model_names)
local ui_add_model_name = ui.new_textbox("LUA", "B", "Model name")
local ui_add_model_path = ui.new_textbox("LUA", "B", "Model path (.mdl)")
local ui_btn_add_model = ui.new_button("LUA", "B", "Add custom model", function() end)
local ui_btn_del_model = ui.new_button("LUA", "B", "Delete selected model", function() end)

-- Hitsounds
local ui_hit_enable = ui.new_checkbox("LUA", "B", "Enable custom hitsounds")
local ui_hit_random = ui.new_checkbox("LUA", "B", "Enable random hitsounds")
local ui_mute_gunshots = ui.new_checkbox("LUA", "B", "Mute weapon gunshot sounds")
local ui_hit_list = ui.new_listbox("LUA", "B", "Sound list", saved_hitsounds)
local ui_add_hit_path = ui.new_textbox("LUA", "B", "Sound path (.wav)")
local ui_btn_add_hit = ui.new_button("LUA", "B", "Add custom sound", function() end)
local ui_btn_del_hit = ui.new_button("LUA", "B", "Delete selected sound", function() end)

-- Autobuy
local ui_buy_enable = ui.new_checkbox("LUA", "B", "Enable autobuy")
local ui_buy_primary = ui.new_combobox("LUA", "B", "Primary weapon", {"None", "AWP", "SSG08", "SCAR20 / G3SG1", "AK47 / M4"})
local ui_buy_secondary = ui.new_combobox("LUA", "B", "Secondary weapon", {"None", "Deagle", "Dual Berettas", "P250", "Five-Seven / Tec-9"})
local ui_buy_armor = ui.new_checkbox("LUA", "B", "Buy armor (Vest + Helm)")
local ui_buy_defuser = ui.new_checkbox("LUA", "B", "Buy defuse kit")
local ui_buy_zeus = ui.new_checkbox("LUA", "B", "Buy Zeus x27")
local ui_buy_smoke = ui.new_checkbox("LUA", "B", "Buy smoke grenade")
local ui_buy_molotov = ui.new_checkbox("LUA", "B", "Buy molotov / inc")
local ui_buy_he = ui.new_checkbox("LUA", "B", "Buy HE grenade")
local ui_buy_flash = ui.new_checkbox("LUA", "B", "Buy flashbang")

-- Configs Manager
local ui_cfg_name = ui.new_textbox("LUA", "B", "New Config Name")
local ui_cfg_list = ui.new_listbox("LUA", "B", "Saved Configurations", {})
local ui_cfg_save = ui.new_button("LUA", "B", "Save / Create Config", function() end)
local ui_cfg_load = ui.new_button("LUA", "B", "Load Selected Config", function() end)
local ui_cfg_delete = ui.new_button("LUA", "B", "Delete Selected Config", function() end)
local ui_cfg_export = ui.new_button("LUA", "B", "Export Config to Clipboard", function() end)
local ui_cfg_import = ui.new_button("LUA", "B", "Import Config from Clipboard", function() end)

local config_map = {
    wm = ui_watermark, mdl_en = ui_model_enable, mdl_idx = ui_model_list,
    hit_en = ui_hit_enable, hit_rnd = ui_hit_random, mute_gun = ui_mute_gunshots, hit_idx = ui_hit_list,
    buy_en = ui_buy_enable, buy_p = ui_buy_primary, buy_s = ui_buy_secondary,
    buy_arm = ui_buy_armor, buy_def = ui_buy_defuser, buy_zs = ui_buy_zeus,
    buy_smk = ui_buy_smoke, buy_mol = ui_buy_molotov, buy_he = ui_buy_he, buy_flsh = ui_buy_flash
}

local function handle_menu_visibility()
    local current_tab = ui.get(ui_tab)
    ui.set_visible(ui_watermark, current_tab == "Main")

    local model_master = current_tab == "Model changer" and ui.get(ui_model_enable)
    ui.set_visible(ui_model_enable, current_tab == "Model changer")
    ui.set_visible(ui_model_list, model_master)
    ui.set_visible(ui_add_model_name, model_master)
    ui.set_visible(ui_add_model_path, model_master)
    ui.set_visible(ui_btn_add_model, model_master)
    ui.set_visible(ui_btn_del_model, model_master)

    local hit_tab_active = current_tab == "Hitsounds"
    ui.set_visible(ui_hit_enable, hit_tab_active)
    ui.set_visible(ui_mute_gunshots, hit_tab_active)
    local hit_custom_active = hit_tab_active and ui.get(ui_hit_enable)
    ui.set_visible(ui_hit_random, hit_custom_active)
    ui.set_visible(ui_hit_list, hit_custom_active)
    ui.set_visible(ui_add_hit_path, hit_custom_active)
    ui.set_visible(ui_btn_add_hit, hit_custom_active)
    ui.set_visible(ui_btn_del_hit, hit_custom_active)

    local buy_master = current_tab == "Autobuy" and ui.get(ui_buy_enable)
    ui.set_visible(ui_buy_enable, current_tab == "Autobuy")
    ui.set_visible(ui_buy_primary, buy_master)
    ui.set_visible(ui_buy_secondary, buy_master)
    ui.set_visible(ui_buy_armor, buy_master)
    ui.set_visible(ui_buy_defuser, buy_master)
    ui.set_visible(ui_buy_zeus, buy_master)
    ui.set_visible(ui_buy_smoke, buy_master)
    ui.set_visible(ui_buy_molotov, buy_master)
    ui.set_visible(ui_buy_he, buy_master)
    ui.set_visible(ui_buy_flash, buy_master)

    local cfg_active = current_tab == "Configs Manager"
    ui.set_visible(ui_cfg_name, cfg_active)
    ui.set_visible(ui_cfg_list, cfg_active)
    ui.set_visible(ui_cfg_save, cfg_active)
    ui.set_visible(ui_cfg_load, cfg_active)
    ui.set_visible(ui_cfg_delete, cfg_active)
    ui.set_visible(ui_cfg_export, cfg_active)
    ui.set_visible(ui_cfg_import, cfg_active)
end

ui.set_callback(ui_tab, handle_menu_visibility)
ui.set_callback(ui_hit_enable, handle_menu_visibility)
ui.set_callback(ui_model_enable, handle_menu_visibility)
ui.set_callback(ui_buy_enable, handle_menu_visibility)

local function export_to_string(tbl)
    local segments = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            local inner = {}
            for sub_k, sub_v in pairs(v) do
                table.insert(inner, tostring(sub_k) .. "\2" .. tostring(sub_v))
            end
            table.insert(segments, tostring(k) .. "\1T\1" .. table.concat(inner, "\3"))
        else
            table.insert(segments, tostring(k) .. "\1" .. type(v):sub(1,1) .. "\1" .. tostring(v))
        end
    end
    return table.concat(segments, "\4")
end

local function import_from_string(str)
    if not str or str == "" then return nil end
    local tbl = { ui = {}, models = {}, hitsounds = {} }
    for segment in string.gmatch(str, "[^\4]+") do
        local parts = {}
        for part in string.gmatch(segment, "[^\1]+") do table.insert(parts, part) end
        if #parts >= 3 then
            local key, type_flag, val = parts[1], parts[2], parts[3]
            if type_flag == "T" then
                local sub_tbl = {}
                for pair in string.gmatch(val, "[^\3]+") do
                    local sk, sv = string.match(pair, "([^\2]+)\2([^\2]+)")
                    if sk and sv then sub_tbl[sk] = sv end
                end
                if key == "saved_models" then tbl.models = sub_tbl
                elseif key == "saved_hitsounds" then 
                    tbl.hitsounds = {}
                    for _, sv in pairs(sub_tbl) do table.insert(tbl.hitsounds, sv) end
                end
            else
                if type_flag == "b" then val = (val == "true")
                elseif type_flag == "n" then val = tonumber(val) end
                tbl.ui[key] = val
            end
        end
    end
    return tbl
end

local function compile_current_config()
    local cfg = { ui = {}, saved_models = saved_models, saved_hitsounds = saved_hitsounds }
    for k, element in pairs(config_map) do cfg.ui[k] = ui.get(element) end
    return cfg
end

local function apply_compiled_config(cfg)
    if not cfg then return false end
    if cfg.saved_models then
        saved_models = cfg.saved_models
        database.write("demontool_models", saved_models)
        model_names = {}
        for name, _ in pairs(saved_models) do table.insert(model_names, name) end
        ui.update(ui_model_list, model_names)
    end
    if cfg.saved_hitsounds then
        saved_hitsounds = cfg.saved_hitsounds
        database.write("demontool_hitsounds", saved_hitsounds)
        ui.update(ui_hit_list, saved_hitsounds)
    end
    if cfg.ui then
        for k, val in pairs(cfg.ui) do
            if config_map[k] then ui.set(config_map[k], val) end
        end
    end
    handle_menu_visibility()
    return true
end

local function update_configs_listbox()
    local db_cfgs = database.read("demontool_v2_cfgs") or {}
    local names = {}
    for name, _ in pairs(db_cfgs) do table.insert(names, name) end
    ui.update(ui_cfg_list, names)
    return db_cfgs, names
end

ui.set_callback(ui_cfg_save, function()
    local name = ui.get(ui_cfg_name)
    if name == "" then client.log("[demontool] Ошибка: Введите имя конфигурации!") return end
    local db = database.read("demontool_v2_cfgs") or {}
    db[name] = compile_current_config()
    database.write("demontool_v2_cfgs", db)
    ui.set(ui_cfg_name, "")
    update_configs_listbox()
    client.log("[demontool] Конфигурация '" .. name .. "' успешно создана.")
end)

ui.set_callback(ui_cfg_load, function()
    local db, names = update_configs_listbox()
    local sel = ui.get(ui_cfg_list)
    if sel and names[sel + 1] then
        local name = names[sel + 1]
        if apply_compiled_config(db[name]) then
            client.log("[demontool] Конфигурация '" .. name .. "' успешно загружена.")
        end
    end
end)

ui.set_callback(ui_cfg_delete, function()
    local db, names = update_configs_listbox()
    local sel = ui.get(ui_cfg_list)
    if sel and names[sel + 1] then
        local name = names[sel + 1]
        db[name] = nil
        database.write("demontool_v2_cfgs", db)
        update_configs_listbox()
        client.log("[demontool] Конфигурация '" .. name .. "' удалена.")
    end
end)

ui.set_callback(ui_cfg_export, function()
    if not clipboard then client.log("[demontool] Ошибка API: Модуль буфера обмена недоступен.") return end
    local current = compile_current_config()
    local flat_table = {}
    for k,v in pairs(current.ui) do flat_table[k] = v end
    flat_table["saved_models"] = current.saved_models
    flat_table["saved_hitsounds"] = current.saved_hitsounds
    clipboard.set(export_to_string(flat_table))
    client.log("[demontool] Конфиг успешно скопирован в буфер обмена.")
end)

ui.set_callback(ui_cfg_import, function()
    if not clipboard then client.log("[demontool] Ошибка API: Модуль буфера обмена недоступен.") return end
    local data = clipboard.get()
    local imported = import_from_string(data)
    if imported then
        local formatted = { ui = imported.ui, saved_models = imported.models, saved_hitsounds = imported.hitsounds }
        if apply_compiled_config(formatted) then
            client.log("[demontool] Конфиг успешно импортирован из буфера обмена.")
        end
    else
        client.log("[demontool] Ошибка: Не удалось распознать данные конфигурации.")
    end
end)

local function update_model_ui()
    model_names = {}
    for k, _ in pairs(saved_models) do table.insert(model_names, k) end
    ui.update(ui_model_list, model_names)
end

ui.set_callback(ui_btn_add_model, function()
    local name = ui.get(ui_add_model_name)
    local path = ui.get(ui_add_model_path)
    if name ~= "" and path ~= "" then
        saved_models[name] = path
        database.write("demontool_models", saved_models)
        update_model_ui()
        ui.set(ui_add_model_name, "")
        ui.set(ui_add_model_path, "")
    end
end)

ui.set_callback(ui_btn_del_model, function()
    local idx = ui.get(ui_model_list)
    if idx and model_names[idx + 1] then
        saved_models[model_names[idx + 1]] = nil
        database.write("demontool_models", saved_models)
        update_model_ui()
    end
end)

ui.set_callback(ui_btn_add_hit, function()
    local path = ui.get(ui_add_hit_path)
    if path ~= "" then
        table.insert(saved_hitsounds, path)
        database.write("demontool_hitsounds", saved_hitsounds)
        ui.update(ui_hit_list, saved_hitsounds)
        ui.set(ui_add_hit_path, "")
    end
end)

ui.set_callback(ui_btn_del_hit, function()
    local idx = ui.get(ui_hit_list)
    if idx and saved_hitsounds[idx + 1] then
        table.remove(saved_hitsounds, idx + 1)
        database.write("demontool_hitsounds", saved_hitsounds)
        ui.update(ui_hit_list, saved_hitsounds)
    end
end)

update_model_ui()
update_configs_listbox()
handle_menu_visibility()

local function precache_model(modelname)
    local rawprecache_table = find_table(networkstringtablecontainer, "modelprecache")
    if rawprecache_table then
        local precache_table = ffi.cast(class_ptr, rawprecache_table)
        if precache_table then
            local add_string = ffi.cast("add_string_t", precache_table[0][8])
            find_or_load_model(ivmodelinfo, modelname)
            if add_string(precache_table, false, modelname, -1, nil) == -1 then return false end
        end
    end
    return true
end

local function change_model(ent, model)
    if model and model:len() > 5 and precache_model(model) then
        local idx = get_model_index(ivmodelinfo, model)
        if idx ~= -1 then
            local raw_entity = get_client_entity(ientitylist, ent)
            if raw_entity then
                local gce_entity = ffi.cast(class_ptr, raw_entity)
                local a_set_model_index = ffi.cast("set_model_index_t", gce_entity[0][75])
                if a_set_model_index ~= nil then a_set_model_index(gce_entity, idx) end
            end
        end
    end
end

client.set_event_callback("pre_render", function()
    if not ui.get(ui_model_enable) then return end
    local me = entity.get_local_player()
    if me == nil or not entity.is_alive(me) then return end

    local current_selection = ui.get(ui_model_list)
    if current_selection and model_names[current_selection + 1] then
        local path = saved_models[model_names[current_selection + 1]]
        if path then change_model(me, path) end
    end
end)

client.set_event_callback("player_hurt", function(e)
    if not ui.get(ui_hit_enable) then return end
    if client.userid_to_entindex(e.attacker) == entity.get_local_player() and #saved_hitsounds > 0 then
        local sound = nil
        if ui.get(ui_hit_random) then
            sound = saved_hitsounds[math.random(1, #saved_hitsounds)]
        else
            local sel = ui.get(ui_hit_list)
            if sel then sound = saved_hitsounds[sel + 1] end
        end
        
        if sound and sound ~= "" then
            for i = 1, 3 do client.exec("play " .. sound) end
        end
    end
end)

client.set_event_callback("override_sound", function(ctx)
    if ui.get(ui_mute_gunshots) and ctx.name:find("weapons") and (ctx.name:find("shot") or ctx.name:find("fire")) then
        return false
    end
end)

local function execute_autobuy()
    if not ui.get(ui_buy_enable) then return end
    
    client.delay_call(0.05, function()
        local cmd = ""

        local primary = ui.get(ui_buy_primary)
        if primary == "AWP" then cmd = cmd .. "buy awp;"
        elseif primary == "SSG08" then cmd = cmd .. "buy ssg08;"
        elseif primary == "SCAR20 / G3SG1" then cmd = cmd .. "buy scar20;buy g3sg1;"
        elseif primary == "AK47 / M4" then cmd = cmd .. "buy ak47;buy m4a1;buy m4a1_silencer;" end

        local secondary = ui.get(ui_buy_secondary)
        if secondary == "Deagle" then cmd = cmd .. "buy deagle;"
        elseif secondary == "Dual Berettas" then cmd = cmd .. "buy elite;"
        elseif secondary == "P250" then cmd = cmd .. "buy p250;"
        elseif secondary == "Five-Seven / Tec-9" then cmd = cmd .. "buy fiveseven;buy tec9;" end

        if ui.get(ui_buy_armor) then cmd = cmd .. "buy vesthelm;buy vest;" end
        if ui.get(ui_buy_defuser) then cmd = cmd .. "buy defuser;" end
        if ui.get(ui_buy_zeus) then cmd = cmd .. "buy taser;" end
        if ui.get(ui_buy_smoke) then cmd = cmd .. "buy smokegrenade;" end
        if ui.get(ui_buy_molotov) then cmd = cmd .. "buy molotov;buy incgrenade;" end
        if ui.get(ui_buy_he) then cmd = cmd .. "buy hegrenade;" end
        if ui.get(ui_buy_flash) then cmd = cmd .. "buy flashbang;" end

        if cmd ~= "" then client.exec(cmd) end
    end)
end

client.set_event_callback("round_prestart", execute_autobuy)

client.set_event_callback("paint", function()
    local screen_w, screen_h = client.screen_size()
    local realtime = globals.realtime()
    local time_passed = realtime - script_load_time

    if time_passed < splash_duration then
        local alpha = 0
        local animation_offset = 0 

        local fade_in_time = 0.6
        local fade_out_time = 0.6

        if time_passed < fade_in_time then
            local progress = time_passed / fade_in_time
            alpha = progress * 255
            animation_offset = (1.0 - progress) * 25
        elseif time_passed > (splash_duration - fade_out_time) then
            local progress = (splash_duration - time_passed) / fade_out_time
            alpha = progress * 255
            animation_offset = (progress - 1.0) * 25
        else
            alpha = 255
            animation_offset = 0
        end

        alpha = math.floor(math.max(0, math.min(255, alpha)))

        local box_w, box_h = 320, 150
        local box_x = (screen_w / 2) - (box_w / 2)
        local box_y = (screen_h / 2.5) - (box_h / 2) + animation_offset

        if splash_texture then
            renderer.texture(splash_texture, box_x, box_y, box_w, box_h, 255, 255, 255, alpha)
        else
            renderer.rectangle(box_x, box_y, box_w, box_h, 14, 14, 14, math.min(alpha, 245))
        end
        
        renderer.gradient(box_x, box_y, box_w, 2, 59, 171, 245, alpha, 186, 85, 211, alpha, true)
        
        renderer.text(box_x + (box_w / 2), box_y + box_h - 45, 255, 255, 255, alpha, "c+", 0, "DEMONTOOL")
        renderer.text(box_x + (box_w / 2), box_y + box_h - 25, 160, 160, 160, alpha, "c", 0, "premium modification initialized")
        
        local progress_factor = math.min(1.0, time_passed / splash_duration)
        local bar_w = math.floor((box_w - 30) * progress_factor)
        
        renderer.rectangle(box_x + 15, box_y + box_h - 10, box_w - 30, 3, 30, 30, 30, math.min(alpha, 150))
        renderer.gradient(box_x + 15, box_y + box_h - 10, bar_w, 3, 59, 171, 245, alpha, 186, 85, 211, alpha, true)
    end

    if ui.get(ui_watermark) then
        local wm_text = "demontool | gamesense"
        renderer.rectangle(screen_w - 170, 15, 160, 22, 14, 14, 14, 200)
        renderer.gradient(screen_w - 170, 15, 160, 2, 59, 171, 245, 255, 186, 85, 211, 255, true)
        renderer.text(screen_w - 90, 26, 255, 255, 255, 255, "c", 0, wm_text)
    end
end)