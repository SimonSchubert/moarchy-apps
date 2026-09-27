// The Trakt app this plugin signs in as, registered at
// https://trakt.tv/oauth/applications with the redirect URI
// urn:ietf:wg:oauth:2.0:oob (the device flow).
//
// An app whose source is public cannot keep a secret: this one identifies
// the app, it protects nobody's account. The device flow still needs the
// person to approve the app on trakt.tv, and every token is theirs alone.
// Settings can name a different app instead.
export var CLIENT_ID = "FfaAy3QK7UmKwSgD3KP-Q4LbdHuki64OZBNNb44_ibc"
export var CLIENT_SECRET = "Nezbd-pNTJDVPaoOG08jQG5LpJyrZ_YQzUjogOlplhY"
