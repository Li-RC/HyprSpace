public let stableAeroSpaceAppId: String = "bobko.aerospace"
#if DEBUG
    public let aeroSpaceAppId: String = "bobko.aerospace.debug"
    public let aeroSpaceAppName: String = "HyprSpace-Debug"
#else
    public let aeroSpaceAppId: String = stableAeroSpaceAppId
    public let aeroSpaceAppName: String = "HyprSpace"
#endif
