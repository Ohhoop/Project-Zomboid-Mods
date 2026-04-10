QuickRestartRestore = QuickRestartRestore or {}

function QuickRestartRestore.applyAuthoritativeSnapshot(player, snapshot)
    if not player or type(snapshot) ~= "table" then
        return false, "invalid_snapshot"
    end

    if type(snapshot.traits) ~= "table" and type(snapshot.skills) ~= "table" then
        return false, "missing_restore_data"
    end

    if type(snapshot.traits) == "table" then
        QuickRestartTraits.applyToPlayer(player, snapshot.traits)
    end

    if type(snapshot.skills) == "table" then
        QuickRestartSkills.applyToPlayer(player, snapshot.skills)
    end

    return true, nil
end

return QuickRestartRestore
