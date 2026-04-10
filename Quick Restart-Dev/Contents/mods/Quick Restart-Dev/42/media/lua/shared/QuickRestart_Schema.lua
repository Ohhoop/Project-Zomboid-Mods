QuickRestartSchema = QuickRestartSchema or {}

function QuickRestartSchema.newSnapshot()
    return {
        meta = {
            version = QuickRestartConstants and QuickRestartConstants.SCHEMA_VERSION or 2,
            source = nil,
            mode = nil,
            createdAt = nil,
        },
        identity = {
            forename = nil,
            surname = nil,
            gender = nil,
            profession = nil,
        },
        world = {
            region = nil,
            isChallenge = false,
            challengeID = nil,
        },
        voice = {},
        visual = {},
        traits = {},
        skills = {},
        clothing = {},
        sandbox = {},
    }
end

return QuickRestartSchema
