import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "kit/Glyphs.js" as KG
import "kit/Json.js" as KJ
import "Address.js" as Address
import "Compose.js" as Compose
import "Helper.js" as Helper
import "Mailbox.js" as Mailbox
import "Store.js" as MailStore
import "Glyphs.js" as G

// Mail: one account, its folders, and the messages in them.
//
//     omarchy-shell shell toggle org.moarchy.mail
//
// Every word said to a server goes through libexec/moarchy-mail, one process
// per request, because QML cannot open a TLS socket; the app keeps what it was
// told in JSON files it alone writes, so a folder draws from the file first
// and from the server when it answers. Inside the Omarchy shell the plugin is
// kept loaded, and every fifteen minutes it asks the Inbox what is new -- one
// short run of the helper, not a process sitting on a connection.
//
// No HTML is drawn. The helper turns a message into text and links, and what
// reaches a Text has no tag in it the helper did not write.
//
// A phone gets the plugin's screens, one at a time: a folder, the folders, a
// message, writing. A desktop gets them side by side: the folders, the
// folder, and the message or the one being written.
App {
  id: root

  appId: "org.moarchy.mail"
  title: "Mail"
  heading: screen === "setup" ? (editingAccount ? "Account" : "Mail") : folderLabel
  subtitle: screen === "setup" ? (editingAccount ? "" : "Sign in")
    : syncing ? "Checking for mail…"
    : syncError ? "Not up to date"
    : unseen > 0 ? unseen + " unread" : (account ? account.email : "")
  windowWidth: 1280
  windowHeight: 820

  store: Store { name: "moarchy-mail" }

  launcher.desktopId: "org.moarchy.Mail"
  launcher.genericName: "Email"
  launcher.comment: "Read and write email"
  launcher.categories: "Network;Email;"
  launcher.keywords: "email;mail;imap;smtp;inbox;"

  mark: Component { Image { source: root.appDir + "/icon.svg"; sourceSize: Qt.size(60, 60) } }

  ui: Tokens {
    theme: root.hostTheme
    compact: root.compact
    readonly property color star: hue("yellow", "#facc15", "#ca8a04")
    readonly property color unsent: bad
  }

  // The phone's own header is the app's only on a folder and the first
  // sign-in; every other screen brings a header with a way back.
  header: !compact || screen === "list" || (screen === "setup" && !account)

  actions: Component {
    Row {
      spacing: 2
      IconButton {
        visible: root.account !== null && root.screen !== "setup" && root.compact
        app: root
        glyph: G.folders
        label: "Folders"
        onClicked: root.showFolders()
      }
      IconButton {
        visible: root.account !== null && root.screen !== "setup"
        app: root
        glyph: KG.search
        label: "Search"
        active: root.searching
        onClicked: root.searching ? root.endSearch() : root.startSearch()
      }
      IconButton {
        visible: root.account !== null && root.screen !== "setup"
        app: root
        glyph: KG.refresh
        label: "Check for mail"
        active: root.syncing
        onClicked: root.refresh(false)
      }
      Button {
        visible: root.account !== null && root.screen !== "setup" && !root.compact
        anchors.verticalCenter: parent.verticalCenter
        app: root
        primary: true
        glyph: G.compose
        text: "Write"
        onClicked: root.startCompose(Compose.blank(Date.now()), "list")
      }
    }
  }

  settings: Component {
    SettingsPage {
      app: root
      blurb: "One account over IMAP and SMTP. No HTML drawn, and new mail noticed with the window closed."
      SettingsSection {
        app: root
        width: parent.width
        title: "Account"
        note: root.account
          ? (root.account.name ? root.account.name + " · " : "") + root.account.email
            + "\nIncoming " + root.account.imap.host + " · outgoing " + root.account.smtp.host
          : "Not signed in."
        Row {
          spacing: 8
          Chip {
            visible: root.account !== null
            app: root
            text: "Change servers or password"
            onClicked: root.startSetup(true)
          }
          Chip {
            visible: root.account !== null
            app: root
            text: "Sign out"
            tint: root.ui.bad
            onClicked: signOut.open()
          }
          Chip {
            visible: root.account === null
            app: root
            text: "Sign in"
            onClicked: root.startSetup(false)
          }
        }
      }
      AppearanceSection { app: root }
      LauncherSection { app: root }
      KeysSection {
        app: root
        keys: [
          ["j k  ↑ ↓", "The next or the previous message"],
          ["Enter", "Open it"],
          ["c", "Write a message"],
          ["r  a  f", "Reply, reply all, forward"],
          ["s  u", "Star it; mark it read or unread"],
          ["Delete", "Move it to Trash"],
          ["/", "Search the messages on this computer"],
          ["Ctrl+Enter", "Send, while writing"],
          [",", "Settings"],
          ["Esc", "Back one step"]
        ]
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "Where it keeps things"
        note: "~/.local/share/moarchy-mail: the account, the folder list, the messages already fetched and the drafts. The password is in a file of its own there, 0600 in a 0700 folder, and goes to nobody but the servers above."
      }
      SettingsSection {
        app: root
        width: parent.width
        title: "New mail"
        note: "Inside the Omarchy shell, Mail looks at the Inbox every fifteen minutes with its window closed, and says so when something has come. Run on its own, it looks only while the window is open."
      }
    }
  }

  // ------------------------------------------------------------ settings

  readonly property bool offline: (Quickshell.env("MOARCHY_MAIL_OFFLINE") || "") !== ""
  // The helper: beside the app in the tree, and in /usr/lib when packaged,
  // because /usr/share holds no programs.
  readonly property string helper: Quickshell.env("MOARCHY_MAIL_HELPER")
    || (appDir === "/usr/share/moarchy-mail" ? "/usr/lib/moarchy-mail/moarchy-mail" : appDir + "/libexec/moarchy-mail")

  readonly property string dataDir: KJ.dataDir("mail", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_MAIL_DIR"))
  readonly property string contactsPath: KJ.dataDir("contacts", Quickshell.env("HOME"), Quickshell.env("XDG_DATA_HOME"),
    Quickshell.env("MOARCHY_CONTACTS_DIR")) + "/contacts.json"

  // The helper draws quoted text in this, because it cannot know the theme.
  readonly property string quoteInk: "#8a8a8f"
  // A folder drawn from its file is refreshed when it is older than this.
  readonly property int staleMs: 2 * 60 * 1000
  readonly property int peekMs: 15 * 60 * 1000

  // ------------------------------------------------------------ state

  // "setup" | "list" | "folders" | "message" | "compose". On a desktop the
  // folder is always on screen, and this is what is beside it.
  property string screen: "list"
  property bool warm: false
  property bool everShown: false

  property var account: null
  property bool accountKnown: false
  property bool editingAccount: false

  property var folders: []
  property bool foldersLoaded: false
  property bool foldersBusy: false

  property bool stateLoaded: false
  property string folder: "INBOX"
  property var inbox: ({ uidvalidity: 0, uidnext: 0, account: "" })
  property var drafts: []
  property var outbox: []

  property var box: Mailbox.empty("INBOX")
  property bool boxLoaded: false
  property string syncingFolder: ""
  property bool loadingOlder: false
  property string syncError: ""
  property var pending: ({})
  property int seq: 0
  property bool peeking: false
  property bool peekDue: false

  property var people: []
  property real now: Date.now()

  property var openRow: null
  property var body: null
  property bool bodyLoading: false
  property string bodyError: ""

  property var compose: Compose.blank(0)
  property string composeFrom: "list"
  property int composeRevision: 0

  property string setupError: ""
  property string setupNote: ""
  property bool signingIn: false

  property bool searching: false
  property string query: ""
  // The keyboard's place in the list, on a desktop.
  property int cursor: -1

  property var readQueue: []
  property var actQueue: []

  readonly property bool wide: !compact
  // Room for the folders as a column of their own beside the list.
  readonly property bool folderColumn: wide && contentArea.width >= 1000

  readonly property bool syncing: syncingFolder !== "" && syncingFolder === folder
  readonly property string folderLabel: account ? MailStore.label(folders, folder) : "Mail"
  readonly property string folderRole: {
    var f = MailStore.find(folders, folder)
    return f ? f.role : (folder === "INBOX" ? "inbox" : "")
  }
  readonly property string sentFolder: MailStore.byRole(folders, "sent")
  readonly property string trashFolder: MailStore.byRole(folders, "trash")
  readonly property string archiveFolder: MailStore.byRole(folders, "archive")
  readonly property string junkFolder: MailStore.byRole(folders, "junk")
  readonly property int unseen: Mailbox.unseen(box, pending)

  // What is drawn is only built while somebody can see it.
  readonly property bool showing: opened
  readonly property bool listVisible: showing && account !== null && screen !== "setup"
    && (wide || screen === "list")
  readonly property var rows: {
    if (!listVisible) return []
    var all = Mailbox.view(box, pending)
    var q = query.trim().toLowerCase()
    if (!searching || !q) return all
    return all.filter(function (r) {
      return (r.subject || "").toLowerCase().indexOf(q) >= 0
        || Address.label(r.from).toLowerCase().indexOf(q) >= 0
        || (r.from && r.from.email || "").toLowerCase().indexOf(q) >= 0
        || (r.preview || "").toLowerCase().indexOf(q) >= 0
    })
  }
  readonly property var extras: {
    if (!listVisible || folder !== "INBOX" || searching) return []
    var out = []
    for (var i = 0; i < outbox.length; i++) out.push({ kind: "outbox", item: outbox[i] })
    for (var j = 0; j < drafts.length; j++) out.push({ kind: "draft", item: drafts[j] })
    return out
  }
  readonly property var shownRow: Mailbox.shown(folder, openRow, pending)
  readonly property string bodyMarkup: body ? String(body.markup || "").split(quoteInk).join(String(ui.muted)) : ""
  readonly property bool canReplyAll: {
    if (!body || !account) return false
    var both = Address.replyAll(body, account.email)
    return both.to.length + both.cc.length > 1
  }

  // ------------------------------------------------------------ the host

  onSummoned: function (payload) {
    everShown = true
    warmUp()
    now = Date.now()
    var ask = Compose.parsePayload(JSON.stringify(payload || {}), Date.now())
    if (ask.draft) startCompose(ask.draft, screen === "compose" ? "list" : screen)
    Qt.callLater(whenReady)
  }

  // Back, before the kit's own: out of what is being written, the message,
  // the folders, a search.
  stepBack: function () {
    if (screen === "compose") { leaveCompose(); return true }
    if (screen === "message") { closeMessage(); return true }
    if (screen === "folders") { screen = "list"; return true }
    if (screen === "setup" && account) { screen = "list"; editingAccount = false; return true }
    if (searching) { endSearch(); return true }
    return false
  }

  function warmUp() {
    if (warm) return
    warm = true
    ensureDir.running = true
  }

  // Everything that waits on the files having been read, and on a window.
  function whenReady() {
    if (!account || !stateLoaded || !boxLoaded || !showing) return
    if (Date.now() - box.at > staleMs) refresh(false)
    if (foldersLoaded && folders.length === 0) refreshFolders()
  }

  function showFolders() {
    screen = "folders"
    if (folders.length === 0 || !foldersBusy) refreshFolders()
  }

  function startSearch() {
    searching = true
    if (!wide) screen = "list"
  }
  function endSearch() {
    searching = false
    query = ""
    resetFocus()
  }

  // ------------------------------------------------------------ jobs
  //
  // Two lanes, so that opening a message is not queued behind a folder that
  // is taking its time. "read" is refreshing: sync, folders, peek,
  // autoconfig. "act" is everything a person did: open, mark, move, send,
  // sign in.

  function run(verb, input, lane, context, urgent) {
    var job = { verb: verb, input: input || {}, context: context || {} }
    var queue = lane === "read" ? readQueue : actQueue
    if (urgent) queue.unshift(job)
    else queue.push(job)
    pump(lane)
  }

  function pump(lane) {
    var proc = lane === "read" ? readLane : actLane
    var queue = lane === "read" ? readQueue : actQueue
    if (proc.running || proc.job || queue.length === 0) return
    var job = queue.shift()
    if (offline) {
      Qt.callLater(function () {
        root.finished(job, { ok: false, kind: "offline", error: "Mail is offline here." })
        root.pump(lane)
      })
      return
    }
    proc.job = job
    proc.stdinEnabled = true
    proc.command = Helper.command(helper, job.verb)
    proc.running = true
  }

  function finished(job, answer) {
    switch (job.verb) {
    case "autoconfig": autoconfigured(job, answer); break
    case "setup": setUp(job, answer); break
    case "forget": forgotten(answer); break
    case "folders": foldersListed(answer); break
    case "sync": synced(job, answer); break
    case "peek": peeked(answer); break
    case "body": bodyFetched(job, answer); break
    case "attachment": attachmentSaved(job, answer); break
    case "flag": case "move": case "delete": changed(job, answer); break
    case "send": mailSent(job, answer); break
    }
  }

  // ------------------------------------------------------------ files

  function cachePath(name) {
    var email = account ? account.email : ""
    return dataDir + "/cache/" + Qt.md5(email + "\n" + name) + ".json"
  }

  function saveState() {
    if (!stateLoaded) return
    stateFile.setText(MailStore.serializeState({ folder: folder, inbox: inbox, drafts: drafts, outbox: outbox }))
  }

  function saveBox() {
    if (!boxLoaded || !boxFile.path) return
    boxFile.setText(Mailbox.serialize(box))
  }

  function saveFolders() {
    if (!foldersLoaded || !account) return
    foldersFile.setText(MailStore.serializeFolders(folders, account.email))
  }

  // ------------------------------------------------------------ a folder

  function openFolder(name) {
    if (screen === "folders" || (screen === "message" && !wide)) screen = "list"
    if (name === folder && boxLoaded) {
      refresh(false)
      return
    }
    if (screen === "message") closeMessage()
    folder = name
    box = Mailbox.empty(name)
    boxLoaded = false
    loadingOlder = false
    syncError = ""
    cursor = -1
    saveState()
  }

  function refresh(older) {
    if (!account || !boxLoaded) return
    if (older) {
      if (loadingOlder) return
      loadingOlder = true
    } else if (syncing) {
      return
    }
    syncingFolder = folder
    run("sync", { folder: folder, uidvalidity: box.uidvalidity, uids: Mailbox.uids(box), limit: 50, older: older },
        "read", { folder: folder, older: older }, false)
  }

  function synced(job, answer) {
    if (job.context.folder !== folder) return
    syncingFolder = ""
    if (job.context.older) loadingOlder = false
    if (!answer.ok) {
      syncError = answer.kind === "offline" ? "" : answer.error
      return
    }
    syncError = ""
    box = Mailbox.merge(box, answer, Date.now())
    saveBox()
    folders = MailStore.withCounts(folders, folder, answer.unseen, answer.exists)
    saveFolders()
    if (folder === "INBOX") noteInbox(answer.uidvalidity, answer.uidnext)
  }

  function refreshFolders() {
    if (!account || foldersBusy) return
    foldersBusy = true
    run("folders", {}, "read", {}, false)
  }

  function foldersListed(answer) {
    foldersBusy = false
    if (!answer.ok) {
      if (!Helper.quiet(answer) && screen === "folders") toast(answer.error)
      return
    }
    folders = MailStore.parseFolders(answer)
    saveFolders()
    if (folder !== "INBOX" && !MailStore.find(folders, folder)) openFolder("INBOX")
  }

  // ------------------------------------------------------------ new mail

  function noteInbox(uidvalidity, uidnext) {
    var email = account ? account.email : ""
    var same = inbox.uidvalidity === uidvalidity && inbox.account === email
    inbox = { uidvalidity: uidvalidity, uidnext: same ? Math.max(inbox.uidnext, uidnext) : uidnext, account: email }
    saveState()
  }

  // Asked for by a timer that may fire before the files are read.
  function peekWhenReady() {
    if (!peekDue || !account || !stateLoaded) return
    peekDue = false
    peek()
  }

  function peek() {
    if (!account || peeking || !stateLoaded) return
    peeking = true
    var same = inbox.account === account.email
    run("peek", { uidvalidity: same ? inbox.uidvalidity : 0, since: same ? inbox.uidnext : 0 }, "read", {}, false)
  }

  function peeked(answer) {
    peeking = false
    if (!answer.ok || !account) return
    var known = inbox.account === account.email && inbox.uidvalidity === answer.uidvalidity
    var fresh = known && inbox.uidnext > 0 ? (answer.rows || []) : []
    noteInbox(answer.uidvalidity, answer.uidnext)
    var inboxFolder = MailStore.find(folders, "INBOX")
    folders = MailStore.withCounts(folders, "INBOX", answer.unseen, inboxFolder ? inboxFolder.total : 0)
    saveFolders()
    if (fresh.length) arrived(fresh)
  }

  function arrived(list) {
    now = Date.now()
    if (folder === "INBOX" && showing) refresh(false)
    if (showing && folder === "INBOX" && screen !== "setup") return
    // feedbackd's sound for it, where there is feedbackd. fbcli ends on the
    // first byte it can read from stdin, so the pipe is held open.
    ping.command = ["sh", "-c", "command -v fbcli >/dev/null 2>&1 || exit 0\nexec fbcli -E message-new-email -t -1 -w 30", "fbcli"]
    ping.running = true
    if (list.length === 1) {
      Quickshell.execDetached(notifyCommand(Address.label(list[0].from) || "New mail", list[0].subject || "No subject"))
    } else {
      var names = list.map(function (r) { return Address.label(r.from) })
      Quickshell.execDetached(notifyCommand(list.length + " new messages", names.join(", ")))
    }
  }

  function notifyCommand(title, text) {
    return ["sh", "-c",
            "if command -v omarchy-notification-send >/dev/null 2>&1; then exec omarchy-notification-send \"$1\" \"$2\" >/dev/null 2>&1; fi\n" +
            "command -v notify-send >/dev/null 2>&1 && exec notify-send -a Mail \"$1\" \"$2\"",
            "sh", title, text]
  }

  // ------------------------------------------------------------ a message

  function openMessage(row) {
    openRow = row
    body = null
    bodyError = ""
    bodyLoading = true
    screen = "message"
    var i = indexOfRow(row.uid)
    if (i >= 0) cursor = i
    var path = Mailbox.bodyPath(dataDir, Qt.md5(folder), box.uidvalidity, row.uid)
    if (bodyFile.path === path) bodyFile.reload()
    else bodyFile.path = path
    if (!Mailbox.has(row, Mailbox.SEEN)) setFlag([row.uid], "seen", true)
  }

  function closeMessage() {
    screen = "list"
    openRow = null
    body = null
    bodyFile.path = ""
  }

  function fetchBody() {
    if (!openRow) return
    bodyLoading = true
    bodyError = ""
    run("body", { folder: folder, uidvalidity: box.uidvalidity, uid: openRow.uid },
        "act", { folder: folder, uid: openRow.uid }, true)
  }

  function bodyFetched(job, answer) {
    if (!openRow || job.context.uid !== openRow.uid || job.context.folder !== folder) return
    bodyLoading = false
    if (answer.ok) {
      body = answer
      return
    }
    bodyError = answer.kind === "offline" ? "This message has not been downloaded." : answer.error
    if (answer.kind === "gone") {
      box = Mailbox.without(box, [job.context.uid])
      saveBox()
    }
  }

  // A link is "#n" into body.links. Mail's own open in a message to write;
  // anything else is shown before it is opened, because the words of a link
  // and where it goes are two different claims.
  function followLink(link) {
    if (!body) return
    var href = (body.links || [])[parseInt(String(link).slice(1), 10)]
    if (!href) return
    if (/^mailto:/i.test(href)) {
      startCompose(Compose.fromMailto(href, Date.now()), "message")
      return
    }
    sheet.show("Open this link?", [
      { text: "Open link", glyph: G.open, run: function () { Quickshell.execDetached(["xdg-open", href]) } },
      { text: "Copy link", glyph: G.copy, run: function () { root.copyText(href, "Link copied") } }
    ], href)
  }

  function copyText(text, said) {
    clip.text = text
    clip.selectAll()
    clip.copy()
    clip.text = ""
    toast(said)
  }

  function saveAttachment(file) {
    if (!openRow) return
    toast("Saving " + file.name + "…")
    run("attachment", { folder: folder, uidvalidity: box.uidvalidity, uid: openRow.uid, index: file.index },
        "act", { name: file.name }, true)
  }

  function attachmentSaved(job, answer) {
    if (!answer.ok) { toast(answer.error); return }
    toast("Saved to Downloads")
    Quickshell.execDetached(["xdg-open", answer.path])
  }

  // ------------------------------------------------------------ marking, moving

  function setFlag(uids, what, on) {
    seq += 1
    var flag = what === "seen" ? Mailbox.SEEN : Mailbox.FLAGGED
    pending = Mailbox.withPending(pending, folder, uids, what, on, seq)
    run("flag", { folder: folder, uids: uids, add: on ? [flag] : [], remove: on ? [] : [flag] },
        "act", { folder: folder, uids: uids, what: what, on: on, flag: flag, seq: seq }, false)
  }

  function toggleStar(row) {
    var r = Mailbox.shown(folder, row, pending)
    if (r) setFlag([r.uid], "flagged", !Mailbox.has(r, Mailbox.FLAGGED))
  }

  function toggleRead(row) {
    var r = Mailbox.shown(folder, row, pending)
    if (r) setFlag([r.uid], "seen", !Mailbox.has(r, Mailbox.SEEN))
  }

  function moveTo(uids, target, said) {
    seq += 1
    pending = Mailbox.withPending(pending, folder, uids, "gone", true, seq)
    run("move", { folder: folder, uids: uids, to: target },
        "act", { folder: folder, uids: uids, what: "gone", seq: seq }, false)
    if (screen === "message" && openRow && uids.indexOf(openRow.uid) >= 0) closeMessage()
    if (said) toast(said)
  }

  // To Trash, or -- in Trash, or with no Trash -- gone, after asking.
  function remove(row) {
    if (!row) return
    if (trashFolder && folder !== trashFolder) {
      moveTo([row.uid], trashFolder, "Moved to " + MailStore.label(folders, trashFolder))
      return
    }
    deleteForGood.open(row)
  }

  function destroy_(row) {
    seq += 1
    pending = Mailbox.withPending(pending, folder, [row.uid], "gone", true, seq)
    run("delete", { folder: folder, uids: [row.uid] },
        "act", { folder: folder, uids: [row.uid], what: "gone", seq: seq }, false)
    if (screen === "message" && openRow && openRow.uid === row.uid) closeMessage()
    toast("Deleted")
  }

  function changed(job, answer) {
    var c = job.context
    pending = Mailbox.clearPending(pending, c.folder, c.uids, c.what, c.seq)
    if (!answer.ok) {
      if (answer.kind !== "offline") toast(answer.error)
      return
    }
    if (c.folder !== folder) return
    if (c.what === "gone") box = Mailbox.without(box, c.uids)
    else box = Mailbox.withFlag(box, c.uids, c.flag, c.on)
    saveBox()
    folders = MailStore.withCounts(folders, folder, box.unseen, box.exists)
    saveFolders()
  }

  // A message in the list, held (or right-clicked).
  function rowMenu(row) {
    var r = Mailbox.shown(folder, row, pending) || row
    var unread = !Mailbox.has(r, Mailbox.SEEN)
    var starred = Mailbox.has(r, Mailbox.FLAGGED)
    sheet.show(r.subject || "No subject", [
      { text: unread ? "Mark as read" : "Mark as unread", glyph: unread ? G.read : G.unread,
        run: function () { root.setFlag([r.uid], "seen", unread) } },
      { text: starred ? "Remove the star" : "Star", glyph: starred ? G.starOutline : G.star,
        run: function () { root.setFlag([r.uid], "flagged", !starred) } },
      { text: "Archive", glyph: G.archive, visible: archiveFolder !== "" && folder !== archiveFolder,
        run: function () { root.moveTo([r.uid], root.archiveFolder, "Archived") } },
      { text: folder === junkFolder ? "Not junk" : "Junk", glyph: G.junk, visible: junkFolder !== "",
        run: function () {
          var toInbox = root.folder === root.junkFolder
          root.moveTo([r.uid], toInbox ? "INBOX" : root.junkFolder, toInbox ? "Moved to the Inbox" : "Moved to Junk")
        } },
      { text: trashFolder && folder !== trashFolder ? "Delete" : "Delete for good", glyph: G.trash, destructive: true,
        run: function () { root.remove(r) } }
    ], Address.label(r.from))
  }

  // The message's own menu, from its header.
  function messageMenu() {
    if (!openRow) return
    var r = openRow
    sheet.show(r.subject || "No subject", [
      { text: "Mark as unread", glyph: G.unread,
        run: function () { root.setFlag([r.uid], "seen", false); root.closeMessage() } },
      { text: "Archive", glyph: G.archive, visible: archiveFolder !== "" && folder !== archiveFolder,
        run: function () { root.moveTo([r.uid], root.archiveFolder, "Archived") } },
      { text: "Junk", glyph: G.junk, visible: junkFolder !== "" && folder !== junkFolder,
        run: function () { root.moveTo([r.uid], root.junkFolder, "Moved to Junk") } },
      { text: "Copy the text", glyph: G.copy, visible: body !== null,
        run: function () { root.copyText(root.body.text, "Copied") } }
    ])
  }

  // A draft or an unsent message, held.
  function extraMenu(extra) {
    sheet.show(Compose.summary(extra.kind === "outbox" ? extra.item.draft : extra.item), [
      { text: "Open", glyph: G.draft, run: function () { root.openExtra(extra) } },
      { text: "Throw away", glyph: G.trash, destructive: true, run: function () { throwAway.open(extra) } }
    ])
  }

  // ------------------------------------------------------------ writing

  function startCompose(draft, from) {
    compose = draft
    composeFrom = from || "list"
    composeRevision += 1
    screen = "compose"
  }

  // What is in the form now, or the draft as it was if the form is gone.
  function typedDraft() {
    var form = composeForm()
    return form ? form.typed() : compose
  }

  // The form is wherever the compose screen is drawn this width.
  property var composeView: null
  function composeForm() { return screen === "compose" ? composeView : null }

  function afterCompose() {
    screen = composeFrom === "message" && openRow ? "message" : "list"
  }

  // Back keeps what was written, unless nothing was.
  function leaveCompose() {
    var d = typedDraft()
    if (Compose.isEmpty(d) || Compose.untouched(d)) {
      drafts = MailStore.withoutId(drafts, d.id)
    } else {
      d.at = Date.now()
      drafts = MailStore.withDraft(drafts, d)
      toast("Kept as a draft")
    }
    saveState()
    afterCompose()
  }

  function discardCompose() {
    var d = typedDraft()
    if (Compose.isEmpty(d) || Compose.untouched(d)) { throwAwayDraft(d.id); return }
    discard.open(d.id)
  }

  function throwAwayDraft(id) {
    drafts = MailStore.withoutId(drafts, id)
    saveState()
    afterCompose()
  }

  function send(anyway) {
    var d = typedDraft()
    var problem = Compose.check(d)
    if (problem) { toast(problem); return }
    if (!d.subject.trim() && !anyway) { noSubject.open(); return }
    var item = { id: "o" + Date.now(), draft: d, status: "sending", error: "", at: Date.now() }
    outbox = outbox.concat([item])
    drafts = MailStore.withoutId(drafts, d.id)
    saveState()
    afterCompose()
    run("send", Compose.request(d, sentFolder), "act", { id: item.id }, false)
  }

  function mailSent(job, answer) {
    if (answer.ok) {
      outbox = MailStore.withoutId(outbox, job.context.id)
      toast(answer.warning || "Sent")
      if (folder === sentFolder) refresh(false)
    } else {
      outbox = MailStore.withStatus(outbox, job.context.id, "failed", answer.error)
      toast("Not sent. It is at the top of the Inbox.")
    }
    saveState()
  }

  function openExtra(extra) {
    if (extra.kind === "draft") { startCompose(extra.item, "list"); return }
    if (extra.item.status === "sending") { toast("Still sending"); return }
    var d = Compose.withFields(extra.item.draft, { error: extra.item.error })
    outbox = MailStore.withoutId(outbox, extra.item.id)
    drafts = MailStore.withDraft(drafts, d)
    saveState()
    startCompose(d, "list")
  }

  function reply(all) {
    if (!body || !account) return
    startCompose(Compose.reply(body, folder, account.email, all, Date.now()), "message")
  }

  function forward() {
    if (!body) return
    startCompose(Compose.forward(body, folder, Date.now()), "message")
  }

  // ------------------------------------------------------------ the account

  property var setupView: null
  function setupForm() { return screen === "setup" ? setupView : null }

  function startSetup(edit) {
    editingAccount = edit && !!account
    setupError = ""
    setupNote = ""
    if (inSettings) setTab(homeTab)
    screen = "setup"
    var form = setupForm()
    if (form) form.fill(editingAccount ? account : null)
  }

  function autoconfigured(job, answer) {
    var form = setupForm()
    if (!answer.ok || !form) return
    if (form.applyServers(job.context.email, answer)) setupNote = answer.note || ""
  }

  function signIn() {
    var form = setupForm()
    if (!form) return
    var request = form.request()
    if (request.email.indexOf("@") < 1) { setupError = "Type your email address first."; return }
    var keeping = editingAccount && Address.same(account.email, request.email)
    if (!request.password.length && !keeping) { setupError = "Type your password."; return }
    if (!request.imap.host || !request.smtp.host) {
      form.showServers = true
      setupError = "The servers are not filled in yet. Give them a moment to be found, or type them in."
      return
    }
    setupError = ""
    signingIn = true
    run("setup", request, "act", {}, true)
  }

  function setUp(job, answer) {
    signingIn = false
    if (!answer.ok) {
      setupError = answer.kind === "offline" ? "Mail is offline here." : answer.error
      return
    }
    var before = account ? account.email : ""
    account = MailStore.parseAccount(answer.account)
    editingAccount = false
    foldersLoaded = true
    folders = MailStore.parseFolders(answer)
    saveFolders()
    if (!account || account.email !== before) {
      folder = "INBOX"
      box = Mailbox.empty("INBOX")
      boxLoaded = false
      pending = ({})
    }
    screen = "list"
    refreshFolders()
    peek()
  }

  function forget() { run("forget", {}, "act", {}, true) }

  function forgotten(answer) {
    if (!answer.ok) { toast(answer.error); return }
    account = null
    folders = []
    folder = "INBOX"
    box = Mailbox.empty("INBOX")
    boxLoaded = false
    pending = ({})
    drafts = []
    outbox = []
    inbox = { uidvalidity: 0, uidnext: 0, account: "" }
    startSetup(false)
  }

  // ------------------------------------------------------------ the keyboard

  function indexOfRow(uid) {
    for (var i = 0; i < rows.length; i++) if (rows[i].uid === uid) return i
    return -1
  }

  function moveCursor(step) {
    if (!rows.length) return
    cursor = Math.max(0, Math.min(rows.length - 1, (cursor < 0 ? (step > 0 ? -1 : rows.length) : cursor) + step))
    if (wide) openMessage(rows[cursor])
  }

  readonly property var cursorRow: cursor >= 0 && cursor < rows.length ? rows[cursor] : null
  // What a key acts on: the message open, else the one the keyboard is on.
  readonly property var keyRow: screen === "message" && openRow ? openRow : cursorRow

  keyHandler: function (event) {
    if (!account || screen === "setup" || screen === "compose") return
    if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
    var k = event.key, t = event.text
    if (k === Qt.Key_Down || t === "j") { moveCursor(1); event.accepted = true; return }
    if (k === Qt.Key_Up || t === "k") { moveCursor(-1); event.accepted = true; return }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter) && cursorRow) { openMessage(cursorRow); event.accepted = true; return }
    if (t === "c") { startCompose(Compose.blank(Date.now()), screen === "message" ? "message" : "list"); event.accepted = true; return }
    if (t === "/") { startSearch(); event.accepted = true; return }
    if (t === "r" && body) { reply(false); event.accepted = true; return }
    if (t === "a" && body) { reply(canReplyAll); event.accepted = true; return }
    if (t === "f" && body) { forward(); event.accepted = true; return }
    if (t === "s" && keyRow) { toggleStar(keyRow); event.accepted = true; return }
    if (t === "u" && keyRow) { toggleRead(keyRow); event.accepted = true; return }
    if (k === Qt.Key_Delete && keyRow) { remove(keyRow); event.accepted = true; return }
  }

  // ------------------------------------------------------------ the harness

  property bool harnessed: false

  function applyHarness() {
    if (harnessed) return
    harnessed = true
    var p = Quickshell.env("MOARCHY_MAIL_PAGE") || ""
    if (p === "folders") showFolders()
    if (p === "settings") setTab("settings")
    if (p === "setup") {
      startSetup(false)
      Qt.callLater(function () {
        var form = root.setupForm()
        if (!form) return
        var typed = (Quickshell.env("MOARCHY_MAIL_TYPED") || "").split("|")
        form.type(typed[0] || "", typed[1] || "", typed[2] || "")
        if ((typed[1] || "").indexOf("@") > 0) {
          var domain = typed[1].split("@")[1]
          root.autoconfigured({ context: { email: typed[1] } }, {
            ok: true, username: typed[1],
            imap: { host: "imap." + domain, port: 993, security: "tls" },
            smtp: { host: "smtp." + domain, port: 465, security: "tls" },
            note: Quickshell.env("MOARCHY_MAIL_NOTE") || ""
          })
        }
        root.setupError = Quickshell.env("MOARCHY_MAIL_ERROR") || ""
      })
    }
    if (p === "compose") {
      var d = Compose.blank(Date.now())
      d.to = Quickshell.env("MOARCHY_MAIL_TO") || ""
      d.subject = Quickshell.env("MOARCHY_MAIL_SUBJECT") || ""
      d.text = Quickshell.env("MOARCHY_MAIL_TYPED") || ""
      startCompose(d, "list")
      // After the form has put the caret where it puts it.
      if ((Quickshell.env("MOARCHY_MAIL_FOCUS") || "") === "to") focusToLater.start()
    }
    if (p === "search") {
      startSearch()
      query = Quickshell.env("MOARCHY_MAIL_QUERY") || ""
    }
    var uid = parseInt(Quickshell.env("MOARCHY_MAIL_OPEN") || "0", 10)
    var row = uid > 0 ? Mailbox.find(box, uid) : null
    if (row) openMessage(row)
    var menu = parseInt(Quickshell.env("MOARCHY_MAIL_MENU") || "0", 10)
    if (menu > 0 && Mailbox.find(box, menu)) rowMenu(Mailbox.find(box, menu))
  }

  Timer {
    id: focusToLater
    interval: 300
    onTriggered: { var f = root.composeForm(); if (f) f.focusTo() }
  }

  function applyBodyHarness() {
    var r = Quickshell.env("MOARCHY_MAIL_REPLY") || ""
    if (!r || screen !== "message") return
    if (r === "forward") forward()
    else reply(r === "all")
  }

  // ------------------------------------------------------------ processes

  // 0700: this directory holds the account, and its password in a file of
  // its own.
  Process { id: ensureDir; running: false; command: ["mkdir", "-p", "-m", "700", root.dataDir, root.dataDir + "/cache"] }

  Lane {
    id: readLane
    onAnswered: function (job, answer) {
      root.finished(job, answer)
      root.pump("read")
    }
  }

  Lane {
    id: actLane
    onAnswered: function (job, answer) {
      root.finished(job, answer)
      root.pump("act")
    }
  }

  Process {
    id: ping
    running: false
    stdinEnabled: true
  }

  // With the window closed, these two are all there is: a first look at the
  // Inbox once the shell has long finished starting, then one short run of
  // the helper every fifteen minutes. Nothing ticks in between.
  Timer {
    interval: 90 * 1000
    running: !root.offline && !root.standalone
    onTriggered: {
      root.peekDue = true
      root.warmUp()
      root.peekWhenReady()
    }
  }

  Timer {
    interval: root.peekMs
    repeat: true
    running: !root.offline && root.account !== null
    onTriggered: root.peek()
  }

  // "3 min ago" moving, and a stale folder refreshed, while it is open.
  Timer {
    interval: 60 * 1000
    repeat: true
    running: root.showing
    onTriggered: {
      root.now = Date.now()
      root.whenReady()
    }
  }

  DataFile {
    id: accountFile
    app: "mail"
    name: "account.json"
    path: root.warm ? root.dataDir + "/account.json" : ""
    onParsed: function (data) {
      if (!accountFile.path) return
      var before = root.account ? root.account.email : ""
      root.account = MailStore.parseAccount(data)
      root.accountKnown = true
      if (!root.account) {
        if (root.screen !== "compose" && root.screen !== "setup") root.startSetup(false)
        Qt.callLater(root.applyHarness)
        return
      }
      if (root.screen === "setup" && !root.editingAccount) root.screen = "list"
      root.peekWhenReady()
      if (root.account.email !== before && before !== "") {
        root.box = Mailbox.empty(root.folder)
        root.boxLoaded = false
      }
      Qt.callLater(root.whenReady)
    }
  }

  DataFile {
    id: stateFile
    app: "mail"
    name: "state.json"
    path: root.warm ? root.dataDir + "/state.json" : ""
    watchChanges: false
    onParsed: function (data) {
      if (!stateFile.path || root.stateLoaded) return
      var state = MailStore.parseState(data)
      root.folder = state.folder
      root.box = Mailbox.empty(state.folder)
      root.inbox = state.inbox
      root.drafts = state.drafts
      root.outbox = state.outbox
      root.stateLoaded = true
      root.peekWhenReady()
    }
  }

  DataFile {
    id: foldersFile
    app: "mail"
    name: "folders.json"
    path: root.warm && root.account ? root.dataDir + "/folders.json" : ""
    watchChanges: false
    onParsed: function (data) {
      if (!foldersFile.path || !root.account) return
      root.folders = MailStore.parseFolders(data, root.account.email)
      root.foldersLoaded = true
      Qt.callLater(root.whenReady)
    }
  }

  DataFile {
    id: boxFile
    app: "mail"
    name: "cache.json"
    path: root.warm && root.account && root.stateLoaded ? root.cachePath(root.folder) : ""
    watchChanges: false
    onParsed: function (data) {
      if (!boxFile.path || root.boxLoaded) return
      root.box = Mailbox.parse(data, root.folder)
      root.boxLoaded = true
      Qt.callLater(root.applyHarness)
      Qt.callLater(root.whenReady)
    }
  }

  // A message's body, as the helper cached it. Missing is the ordinary case
  // for a message not opened before, and asks the server.
  DataFile {
    id: bodyFile
    app: "mail"
    name: "body.json"
    path: ""
    watchChanges: false
    onParsed: function (data) {
      if (!bodyFile.path || !root.openRow) return
      if (data && data.ok === true && data.uid === root.openRow.uid && data.schema === 1) {
        root.body = data
        root.bodyLoading = false
        Qt.callLater(root.applyBodyHarness)
      } else {
        root.fetchBody()
      }
    }
  }

  // Contacts' book, for the To field. Read, never written.
  DataFile {
    id: contactsFile
    app: "contacts"
    name: "contacts.json"
    path: root.warm ? root.contactsPath : ""
    onParsed: function (data) { if (contactsFile.path) root.people = Address.people(data) }
  }

  // The clipboard, reached the one way QML has: a TextEdit asked to copy.
  TextEdit { id: clip; visible: false }

  IpcHandler {
    target: "mail"

    function compose(to: string): string {
      var payload = JSON.stringify({ to: to })
      if (root.shell && typeof root.shell.summon === "function") root.shell.summon(root.pluginId, payload)
      else root.open(payload)
      return "ok"
    }
    function check(): string {
      root.peekDue = true
      root.warmUp()
      root.peekWhenReady()
      return root.accountKnown && !root.account ? "no account" : "checking"
    }
    function refresh(): string {
      root.warmUp()
      root.refresh(false)
      return root.boxLoaded ? "refreshing " + root.folder : "not loaded yet"
    }
    // For testing on the device, where ssh has no finger to press Send with.
    // The message goes through the outbox exactly as a tapped one does.
    function send(to: string, subject: string, text: string): string {
      if (!root.account) return "no account"
      if (!root.stateLoaded) return "not loaded yet"
      var d = Compose.withFields(Compose.blank(Date.now()), { to: to, subject: subject, text: text })
      var problem = Compose.check(d)
      if (problem) return problem
      var item = { id: "o" + Date.now(), draft: d, status: "sending", error: "", at: Date.now() }
      root.outbox = root.outbox.concat([item])
      root.saveState()
      root.run("send", Compose.request(d, root.sentFolder), "act", { id: item.id }, false)
      return item.id
    }
    function star(uid: int): string {
      var row = Mailbox.find(root.box, uid)
      if (!row) return "no such message"
      root.toggleStar(row)
      return "ok"
    }
    function outbox(): string { return JSON.stringify(root.outbox.map(function (o) { return o.status + ": " + o.error })) }
    function unread(): int { return root.unseen }
    function screen(): string { return root.screen }
    function settled(): bool { return root.accountKnown && root.stateLoaded }
  }

  // ------------------------------------------------------------ asking first

  ActionSheet { id: sheet; app: root }

  Dialog {
    id: deleteForGood
    app: root
    title: "Delete this message for good?"
    text: "It is removed from the server, not moved to a Trash folder, and cannot be brought back."
    acceptText: "Delete"
    destructive: true
    onAccepted: root.destroy_(subject)
  }

  Dialog {
    id: throwAway
    app: root
    title: subject && subject.kind === "outbox" ? "Throw away this unsent message?" : "Throw away this draft?"
    text: "What was written in it is gone."
    acceptText: "Throw away"
    destructive: true
    onAccepted: {
      var extra = subject
      if (extra.kind === "draft") root.drafts = MailStore.withoutId(root.drafts, extra.item.id)
      else root.outbox = MailStore.withoutId(root.outbox, extra.item.id)
      root.saveState()
    }
  }

  Dialog {
    id: discard
    app: root
    title: "Throw away this message?"
    text: "It is not sent and not kept as a draft."
    acceptText: "Throw away"
    destructive: true
    onAccepted: root.throwAwayDraft(subject)
  }

  Dialog {
    id: noSubject
    app: root
    title: "Send it without a subject?"
    text: "The subject is the line people decide by whether to open it."
    acceptText: "Send"
    acceptGlyph: G.send
    onAccepted: root.send(true)
  }

  Dialog {
    id: signOut
    app: root
    title: "Sign out?"
    text: "The account, its password and every message kept on this computer are removed. The mail on the server is not touched."
    acceptText: "Sign out"
    destructive: true
    onAccepted: root.forget()
  }

  // ------------------------------------------------------------ the screen

  onOpenedChanged: if (opened) everShown = true

  // Signing in, whatever the width.
  Loader {
    anchors.fill: parent
    active: root.everShown && root.screen === "setup"
    sourceComponent: SetupView { app: root; paged: !root.header }
  }

  // A phone: one screen at a time.
  Item {
    anchors.fill: parent
    visible: !root.wide && root.screen !== "setup"

    Loader {
      anchors.fill: parent
      active: root.everShown && !root.wide && root.account !== null
      visible: root.screen === "list"
      sourceComponent: MailList { app: root }
    }
    Loader {
      anchors.fill: parent
      active: !root.wide && root.screen === "folders"
      sourceComponent: FolderList { app: root; paged: true }
    }
    Loader {
      anchors.fill: parent
      active: !root.wide && root.screen === "message" && root.openRow !== null
      sourceComponent: MessageView { app: root; paged: true }
    }
    Loader {
      anchors.fill: parent
      active: !root.wide && root.screen === "compose"
      sourceComponent: ComposeView { app: root; paged: true }
    }

    // Write: the pencil in the corner, over a folder.
    Rectangle {
      visible: root.screen === "list" && root.account !== null
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 16
      width: 56
      height: 56
      radius: root.ui.radius
      color: fabMouse.pressed ? Qt.darker(root.ui.accent, 1.15) : root.ui.accent
      Accessible.role: Accessible.Button
      Accessible.name: "Write a message"
      Icon {
        anchors.centerIn: parent
        app: root
        text: G.compose
        size: 24
        color: root.ui.inkOnAccent
      }
      MouseArea {
        id: fabMouse
        anchors.fill: parent
        onClicked: root.startCompose(Compose.blank(Date.now()), "list")
      }
    }
  }

  // A desktop: the folders, the folder, and what is open beside it.
  Item {
    anchors.fill: parent
    visible: root.wide && root.screen !== "setup"

    Loader {
      id: folderCol
      active: root.everShown && root.wide && root.folderColumn && root.account !== null
      visible: active
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.leftMargin: 12
      width: active ? 220 : 0
      sourceComponent: FolderList { app: root; paged: false }
    }
    Loader {
      id: listCol
      active: root.everShown && root.wide && root.account !== null
      anchors.left: folderCol.right
      anchors.leftMargin: folderCol.active ? 8 : 0
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.min(420, Math.max(320, (parent.width - folderCol.width) * 0.4))
      sourceComponent: MailList { app: root }
    }
    Rectangle {
      anchors.left: listCol.right
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: 12
      anchors.leftMargin: 8
      radius: root.ui.radius
      color: root.ui.surface
      border.width: 1
      border.color: root.ui.line
      clip: true

      EmptyState {
        anchors.centerIn: parent
        visible: root.screen === "list"
        app: root
        glyph: G.mail
        title: root.rows.length ? "No message open" : ""
        text: root.rows.length ? "Pick one from the list, or press c to write one." : ""
      }
      Loader {
        anchors.fill: parent
        active: root.wide && root.screen === "folders" && !root.folderColumn
        sourceComponent: FolderList { app: root; paged: false }
      }
      Loader {
        anchors.fill: parent
        active: root.wide && root.screen === "message" && root.openRow !== null
        sourceComponent: MessageView { app: root; paged: false }
      }
      Loader {
        anchors.fill: parent
        active: root.wide && root.screen === "compose"
        sourceComponent: ComposeView { app: root; paged: false }
      }
    }
  }
}
