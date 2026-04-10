QuickRestartConstants = QuickRestartConstants or {}

QuickRestartConstants.SCHEMA_VERSION = 2
QuickRestartConstants.MOD_ID = "QuickRestart-DEV"
QuickRestartConstants.MODULE = "QuickRestart"

QuickRestartConstants.COMMANDS = {
    APPLY_SKILLS = "applySkills",
    APPLY_SKILLS_ACK = "applySkillsAck",
    APPLY_SKILLS_RETRY = "applySkillsRetry",
    APPLY_SKILLS_DENIED = "applySkillsDenied",
    SUBMIT_SNAPSHOT = "submitSnapshot",
    SNAPSHOT_ACK = "snapshotAck",
    SNAPSHOT_RETRY = "snapshotRetry",
    REQUEST_ACTIVE_SNAPSHOT = "requestActiveSnapshot",
    SNAPSHOT_DATA = "snapshotData",
    REQUEST_RESTART_SAME_WORLD = "requestRestartSameWorld",
    REQUEST_RESTART_FRESH_WORLD = "requestRestartFreshWorld",
    RESTART_ACCEPTED = "restartAccepted",
    RESTART_DENIED = "restartDenied",
}

QuickRestartConstants.MODE = {
    SOLO = "solo",
    MP = "mp",
}

QuickRestartConstants.SNAPSHOT_SOURCE = {
    LEGACY = "legacy",
    CLIENT = "client",
    SERVER = "server",
}

QuickRestartConstants.RETRY = {
    MAX_SNAPSHOT_ATTEMPTS = 3,
}

QuickRestartConstants.SERVER = {
    RESTART_GRANT_TTL_SECONDS = 900,
}

QuickRestartConstants.VISUAL = {
    F_HAIR_STUBBLE = "Base.F_Hair_Stubble",
    M_HAIR_STUBBLE = "Base.M_Hair_Stubble",
    M_BEARD_STUBBLE = "Base.M_Beard_Stubble",
    INVENTORY_CONTAINER = "InventoryContainer",
}

return QuickRestartConstants
