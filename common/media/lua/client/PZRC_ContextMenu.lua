PZRC_ContextMenu = PZRC_ContextMenu or {}

local SECTION_LABELS = {
    StarterKit     = "IGUI_PZRC_Section_StarterKit",
    Fridge         = "IGUI_PZRC_Section_Fridge",
    InfGen         = "IGUI_PZRC_Section_InfGen",
    Library        = "IGUI_PZRC_Section_Library",
}

local function findOption(context, name)
    if not context or not context.options then return nil end
    for _, opt in pairs(context.options) do
        if opt and opt.name == name then return opt end
    end
    return nil
end

---@param context ISContextMenu
---@return ISContextMenu
function PZRC_ContextMenu.getRoot(context)
    local label = getText("IGUI_PZRC_Menu")
    local existing = findOption(context, label)
    if existing and existing.subOption then
        return context:getSubMenu(existing.subOption)
    end

    local option = context:addOption(label)
    local submenu = ISContextMenu:getNew(context)
    context:addSubMenu(option, submenu)
    return submenu
end

---@param context ISContextMenu
---@param sectionKey string
---@return ISContextMenu
function PZRC_ContextMenu.getSection(context, sectionKey)
    local root = PZRC_ContextMenu.getRoot(context)
    local labelKey = SECTION_LABELS[sectionKey] or sectionKey
    local label = getText(labelKey)

    local existing = findOption(root, label)
    if existing and existing.subOption then
        return root:getSubMenu(existing.subOption)
    end

    local option = root:addOption(label)
    local submenu = ISContextMenu:getNew(root)
    root:addSubMenu(option, submenu)
    return submenu
end
