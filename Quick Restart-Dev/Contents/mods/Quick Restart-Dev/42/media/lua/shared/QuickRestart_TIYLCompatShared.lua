require("QuickRestart_Validate")
require("QuickRestart_Restore")
require("QuickRestart_Randomizer")

if not getActivatedMods():contains("ThisIsYourLife") then
    return false
end

QuickRestartValidate.registerModOwnedModDataKey("TIYL")
QuickRestartRestore.registerSpawnPurgeExemptModDataKey("TIYLPartnerId")
QuickRestartRestore.registerSpawnPurgeExemptModDataKey("TIYLPosterStoryId")
QuickRestartRandomizer.registerSandboxRollExclusion("ThisIsYourLife.")

return true
