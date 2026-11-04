// The Trakt app Couch reads Trakt's public lists as, registered at
// https://trakt.tv/oauth/applications.
//
// A client ID is public by design: Trakt sends it as the trakt-api-key header
// on every request, and it lets nobody into anyone's account. The app's
// client secret is not here, because a secret can't be kept in public
// source. Signing in exchanges a code for tokens with a secret, so it uses
// the person's own Trakt app, set in Settings -> Trakt app.
export var CLIENT_ID = "FfaAy3QK7UmKwSgD3KP-Q4LbdHuki64OZBNNb44_ibc"
