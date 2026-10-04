import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "Glyphs.js" as G
import "Otp.js" as Otp
import "Store.js" as S

// Authenticator: the six-digit codes two-factor sign-in asks for (TOTP, RFC
// 6238), one tap from the clipboard.
//
//     omarchy-shell shell toggle org.moarchy.authenticator
//
// The keys are ~/.local/share/moarchy-authenticator/accounts.json (Store.js),
// in a folder only you can read. They are not encrypted: see the README for
// why, and what does protect them.
//
// Nothing here talks to a network. A code is the key and the clock, through
// HMAC (Otp.js), and the clock is the one thing it needs to be right.
//
// The window ticks once a second while it is open and not at all while it
// is shut. The shell keeps this panel loaded from its own startup, and a
// timer running in a window nobody opened is work the phone pays for.
App {
  id: root

  appId: "org.moarchy.authenticator"
  title: "Authenticator"
  subtitle: !loaded || !accounts.length ? ""
    : list.query !== "" ? shown.length + " of " + accounts.length
    : accounts.length + (accounts.length === 1 ? " account" : " accounts")
  windowWidth: 1080
  windowHeight: 760

  store: Store { name: "moarchy-authenticator"; defaults: ({ hideCodes: false }) }

  launcher.desktopId: "org.moarchy.Authenticator"
  launcher.genericName: "Authenticator"
  launcher.comment: "Two-factor sign-in codes, one tap from the clipboard"
  launcher.categories: "Utility;Security;"
  launcher.keywords: "totp;2fa;otp;authenticator;two-factor;mfa;code;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    // An account's tile takes one of the theme's hues, by issuer, so every
    // login at one place is one colour.
    readonly property var hues: [
      accent,
      hue("green", "#4ade80", "#16a34a"),
      hue("magenta", "#c084fc", "#9333ea"),
      hue("orange", "#fb923c", "#ea580c"),
      hue("cyan", "#22d3ee", "#0891b2"),
      hue("yellow", "#facc15", "#ca8a04"),
      hue("red", "#f87171", "#dc2626")
    ]
    function accountHue(key) { return hues[Otp.hueIndex(key, hues.length)] }
  }

  readonly property var glyphs: ({
    search: KG.search,
    plus: KG.plus,
    remove: KG.remove,
    check: KG.check,
    close: KG.close,
    chevronDown: KG.chevronDown,
    shieldKey: G.shieldKey,
    edit: G.edit,
    copy: G.copy,
    paste: G.paste,
    scan: G.scan,
    show: G.show,
    hide: G.hide,
    link: G.link
  })

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        app: root
        glyph: KG.plus
        label: "Add an account"
        onClicked: root.startNew()
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "The codes two-factor sign-in asks for, one tap from the clipboard. No account, no cloud, no network."
      SettingsSection {
        app: root
        width: parent.width
        title: "Privacy"
        Toggle {
          app: root
          width: parent.width
          text: "Hide codes until tapped"
          note: "For a screen other people can see. A tap shows the code and copies it."
          checked: !!root.store.prefs.hideCodes
          onToggled: function (on) { root.store.set("hideCodes", on) }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["/", "Search"],
          ["Arrows", "Move through the accounts"],
          ["Enter", "Copy the code"],
          ["n", "Add an account"],
          ["e", "Edit the account"],
          ["Delete", "Delete the account, after asking"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps them"
        note: "~/.local/share/moarchy-authenticator/accounts.json, in a folder only you can read. The keys in it are not encrypted: disk encryption and your login are what protect them, as they protect your browser's passwords. Copy that file somewhere safe: it is the backup."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "What it does not do"
        note: "No sync, no cloud backup, no counter-based (HOTP) codes, no Steam codes, and no camera. Codes come from the clock: if they are refused, check the time is set automatically."
      }
    }
  }

  page: Component { AccountEditor { app: root } }

  // ------------------------------------------------------------ the time

  // Milliseconds since the epoch, a second at a time. MOARCHY_AUTHENTICATOR_NOW
  // (seconds) stops the clock there, for the screenshots.
  readonly property real frozen: 1000 * Number(Quickshell.env("MOARCHY_AUTHENTICATOR_NOW") || 0)
  property real now: frozen || Date.now()

  Timer {
    id: tick
    running: root.opened && !root.frozen
    repeat: true
    // Re-aimed at the next whole second every time, so a code turns over
    // when the second does rather than up to a second late.
    interval: 1000
    onTriggered: {
      root.now = Date.now()
      interval = 1000 - root.now % 1000 + 5
    }
  }
  onOpenedChanged: {
    if (opened) {
      if (!frozen) now = Date.now()
      return
    }
    draft = null
    draftIsNew = false
    revealedId = ""
    current = -1
  }

  // ------------------------------------------------------------ the accounts

  property var accounts: []
  // Rows in the file this app cannot draw, written back as they were found.
  property var strays: []
  property bool loaded: false

  readonly property var shown: Otp.filtered(accounts, list.query)

  // The account being edited, a copy, or a blank one being added; or null.
  property var draft: null
  property bool draftIsNew: false
  // Text for the add box: a scan, a paste, MOARCHY_AUTHENTICATOR_ADD.
  property string pendingText: ""
  signal dropText(string text)

  // The keyboard's place in the shown list.
  property int current: -1

  // Codes hidden until tapped: Settings, or MOARCHY_AUTHENTICATOR_HIDE=1.
  readonly property bool hideCodes: !!store.prefs.hideCodes || Quickshell.env("MOARCHY_AUTHENTICATOR_HIDE") === "1"
  // With codes hidden, the one tapped, for a while.
  property string revealedId: ""
  Timer {
    id: revealTimer
    interval: 20000
    onTriggered: root.revealedId = ""
  }

  function dots(n) {
    var out = ""
    for (var i = 0; i < n; i++) out += String.fromCharCode(0x2022)
    return out
  }

  function save() { file.save(S.serialize(accounts, strays) + "\n") }

  function copyCode(id) {
    var a = Otp.find(accounts, id)
    if (!a) return
    if (hideCodes) {
      revealedId = id
      revealTimer.restart()
    }
    var code = Otp.codeAt(a, now)
    Quickshell.clipboardText = code
    toast("Copied " + Otp.grouped(code) + " · " + Otp.title(a))
  }

  function copyLink(id) {
    var a = Otp.find(accounts, id)
    if (!a) return
    Quickshell.clipboardText = Otp.toUri(a)
    toast("Link copied. It holds the key.")
  }

  function pasteKey() {
    var t = String(Quickshell.clipboardText || "").trim()
    if (!t) { toast("Nothing on the clipboard"); return }
    dropText(t)
  }

  function startNew() {
    resetFocus()
    draft = { id: "", issuer: "", name: "", secret: "", algorithm: "SHA1", digits: 6, period: Otp.DEFAULT_PERIOD }
    draftIsNew = true
    if (!compact) probeScan()
    if (!topPage) push({ kind: "account" })
  }

  function openEditor(id) {
    var a = Otp.find(accounts, id)
    if (!a) return
    resetFocus()
    draft = Otp.copy(a)
    draftIsNew = false
    if (!topPage) push({ kind: "account" })
  }

  function closeEditor() {
    draft = null
    draftIsNew = false
    if (topPage) pop()
    resetFocus()
  }

  // New accounts, from the add page or IPC. A key that is already here is
  // the same login, and is left alone. Returns how many went in.
  function addAll(list) {
    var added = 0
    var same = null
    var out = accounts
    for (var i = 0; i < list.length; i++) {
      var dup = Otp.sameKey(out, list[i].secret)
      if (dup) { same = dup; continue }
      var a = Otp.copy(list[i])
      a.id = Otp.newId(Date.now() + i)
      out = Otp.withAccount(out, a)
      added++
    }
    if (added) {
      accounts = out
      save()
    }
    closeEditor()
    if (added === 1) toast("Added " + Otp.title(list[0]))
    else if (added > 1) toast("Added " + added + " accounts" + (same ? ", and skipped what was already here" : ""))
    else if (same) toast("Already here, as " + Otp.title(same))
    return added
  }

  function saveLabels(id, issuer, name) {
    var a = Otp.find(accounts, id)
    if (!a) return
    var b = Otp.copy(a)
    b.issuer = String(issuer || "").trim()
    b.name = String(name || "").trim()
    accounts = Otp.withAccount(accounts, b)
    save()
    closeEditor()
    toast("Saved")
  }

  function askDelete(id) {
    var a = Otp.find(accounts, id)
    if (a) confirmDelete.open(a)
  }

  function remove(id) {
    var a = Otp.find(accounts, id)
    if (!a) return
    accounts = Otp.without(accounts, id)
    save()
    if (draft && draft.id === id) closeEditor()
    current = Math.min(current, shown.length - 1)
    toast("Deleted " + Otp.title(a), "Undo", function () {
      root.accounts = Otp.withAccount(root.accounts, a)
      root.save()
    })
  }

  Dialog {
    id: confirmDelete
    app: root
    readonly property var what: subject || ({ issuer: "", name: "" })
    title: "Delete " + Otp.title(what) + "?"
    text: "Its codes go with it. Turn two-factor sign-in off at " + (what.issuer || "the site") + " first, or move the account to another authenticator. Without a code, or the site's recovery codes, that login is locked."
    acceptText: "Delete"
    acceptGlyph: KG.remove
    destructive: true
    onAccepted: root.remove(what.id)
  }

  // A page popped by Back leaves no draft behind it.
  onStackChanged: if (!stack.length && draft) { draft = null; draftIsNew = false }

  stepBack: function () {
    if (list.query !== "") { list.query = ""; return true }
    return false
  }

  keyHandler: function (event) {
    if (topPage || inSettings) return
    var k = event.key
    var n = shown.length
    var step = k === Qt.Key_Down ? list.columns : k === Qt.Key_Up ? -list.columns
      : k === Qt.Key_Right ? 1 : k === Qt.Key_Left ? -1 : 0
    if (step) {
      if (!n) return
      current = current < 0 ? 0 : Math.max(0, Math.min(n - 1, current + step))
      list.show(current)
      event.accepted = true
      return
    }
    var picked = current >= 0 && current < n ? shown[current].id : (n === 1 ? shown[0].id : "")
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (picked) copyCode(picked)
      event.accepted = true
      return
    }
    if (k === Qt.Key_Delete) {
      if (picked) askDelete(picked)
      event.accepted = true
      return
    }
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    if (event.text === "/") { Qt.callLater(list.focusField); event.accepted = true; return }
    if (event.text === "n") { startNew(); event.accepted = true; return }
    if (event.text === "e") { if (picked) openEditor(picked); event.accepted = true }
  }

  // ------------------------------------------------------------ the file

  DataFile {
    id: file
    app: "authenticator"
    name: "accounts.json"
    onParsed: function (data) {
      var state = S.parse(data)
      root.accounts = state.accounts
      root.strays = state.strays
      root.loaded = true
      root.harness()
    }
    onQuarantined: function (to) { root.toast("The accounts file was unreadable and was kept aside") }
    // Keys are passwords: the folder is yours alone before the first one is
    // written, and the file after every write, whatever the umask said.
    onSaved: Quickshell.execDetached(["chmod", "600", "--", file.path])
    Component.onCompleted: Quickshell.execDetached(["sh", "-c", "mkdir -p -m 700 -- \"$1\" && chmod 700 -- \"$1\"", "sh", file.dir])
  }

  // ------------------------------------------------------------ scanning

  // On a desktop: slurp for a box round the QR code a site is showing, grim
  // for a picture of it, zbarimg to read it. All three are optional, and the
  // button is only there when they are installed. The picture is written
  // into the runtime folder, readable only by you, and deleted at once.
  property bool canScan: false
  property bool scanProbed: false
  readonly property bool scanning: scanProc.running

  function probeScan() {
    if (scanProbed || probe.running) return
    probe.running = true
  }
  Process {
    id: probe
    command: ["sh", "-c", "command -v grim && command -v slurp && command -v zbarimg"]
    // qmllint disable signal-handler-parameters
    onExited: function (code) {
      root.scanProbed = true
      root.canScan = code === 0
    }
    // qmllint enable signal-handler-parameters
  }

  function scanScreen() { if (!scanProc.running) scanProc.running = true }
  Process {
    id: scanProc
    command: ["sh", "-c",
      "umask 077; region=$(slurp) || exit 3; " +
      "f=$(mktemp --suffix=.png \"${XDG_RUNTIME_DIR:-/tmp}/moarchy-authenticator-XXXXXX\") || exit 5; " +
      "grim -t png -g \"$region\" \"$f\" || { rm -f \"$f\"; exit 5; }; " +
      "zbarimg -q --raw \"$f\"; s=$?; rm -f \"$f\"; exit $s"]
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    // qmllint disable signal-handler-parameters
    onExited: function (code) {
      // 3: the box was cancelled. 4: zbarimg found no code in it.
      if (code === 0) root.dropText(String(scanOut.text || "").trim())
      else if (code === 4) root.toast("No QR code in that box")
      else if (code !== 3) root.toast("The scan did not work")
    }
    // qmllint enable signal-handler-parameters
  }

  // MOARCHY_AUTHENTICATOR_PAGE=add: the add page, with _ADD in its box.
  // _EDIT=<issuer>: that account. _SEARCH: a query. For the screenshots.
  property bool harnessed: false
  function harness() {
    if (harnessed) return
    harnessed = true
    var search = Quickshell.env("MOARCHY_AUTHENTICATOR_SEARCH") || ""
    if (search) list.query = search
    var want = Quickshell.env("MOARCHY_AUTHENTICATOR_EDIT") || ""
    var add = (Quickshell.env("MOARCHY_AUTHENTICATOR_PAGE") || "") === "add"
    pendingText = Quickshell.env("MOARCHY_AUTHENTICATOR_ADD") || ""
    // _REVEAL=<issuer>: the one tapped, with _HIDE=1.
    var reveal = Quickshell.env("MOARCHY_AUTHENTICATOR_REVEAL") || ""
    Qt.callLater(function () {
      if (add) { root.startNew(); return }
      for (var i = 0; i < root.accounts.length; i++) {
        var a = root.accounts[i]
        if (want && (a.issuer === want || a.id === want)) { root.openEditor(a.id); return }
        if (reveal && a.issuer === reveal) root.revealedId = a.id
      }
    })
  }

  IpcHandler {
    target: "authenticator"
    // An otpauth:// link (or several, or a key): how many were added.
    function add(text: string): string {
      var r = Otp.read(String(text || ""), Date.now())
      if (r.kind === "key") return "a bare key needs a link: otpauth://totp/Name?secret=KEY"
      if (!r.accounts.length) return r.errors.join("; ") || "nothing to add"
      var before = root.accounts.length
      root.addAll(r.accounts)
      return String(root.accounts.length - before)
    }
    // The current code of the first account whose issuer or name has `query`
    // in it, for a script: `qs ipc call authenticator code github`.
    function code(query: string): string {
      var hits = Otp.filtered(root.accounts, query)
      return hits.length ? Otp.codeAt(hits[0], Date.now()) : ""
    }
    function list(): string {
      return root.accounts.map(function (a) { return Otp.title(a) + (a.issuer ? ":" + a.name : "") }).join("\n")
    }
    function count(): int { return root.accounts.length }
    function close(): string { root.dismiss(); return "ok" }
  }

  // ------------------------------------------------------------ views

  AccountList {
    id: list
    anchors.fill: parent
    app: root
    items: root.shown
    loaded: root.loaded
    total: root.accounts.length
    current: root.current
    onQueryChanged: { root.current = -1; toTop() }
    onCopied: function (id) { root.copyCode(id) }
    onEdited: function (id) { root.openEditor(id) }
  }
}
