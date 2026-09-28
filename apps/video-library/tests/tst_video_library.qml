// Somebody else's JSON, our own file, and every figure on screen.
//
// Nothing here touches the network: the answers are what curl would have
// printed -- a body, a newline, a status -- so the failures worth testing,
// a 429 or a body that is not JSON, can be had on demand.
import QtQuick
import QtTest
import "../Lbry.js" as L

TestCase {
  name: "VideoLibrary"

  readonly property var chan: ({
    claim_id: "affb63e10b2ddc4fbd16520ea7cda3d02f9b982c", name: "@SrLedwis", value_type: "channel",
    canonical_url: "lbry://@SrLedwis#a",
    meta: { claims_in_channel: 233 },
    value: { title: "SrLedwis", thumbnail: { url: "https://thumbnails.lbry.com/UCN" }, description: "Tech" }
  })

  function stream(over) {
    var c = {
      claim_id: "74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20",
      name: "no-tires-tu-vieja-pc-windows-11-vs-linux",
      value_type: "stream",
      canonical_url: "lbry://@SrLedwis#a/no-tires-tu-vieja-pc-windows-11-vs-linux#7",
      timestamp: 1790592847,
      meta: { creation_timestamp: 1790592847 },
      value: {
        title: "No tires tu vieja PC", description: "Windows 11 vs Linux",
        thumbnail: { url: "https://thumbnails.lbry.com/abc" },
        stream_type: "video",
        source: { sd_hash: "67dc70aabbccdd", media_type: "video/mp4", size: "122289526" },
        video: { duration: 2701, width: 1920, height: 1080 },
        tags: ["linux", "c:members-only-not", "windows", "linux"],
        release_time: "1790500000", license: "None", languages: ["es"]
      },
      signing_channel: chan
    }
    for (var k in over) c[k] = over[k]
    return c
  }

  // --- reading claims

  function test_video() {
    var v = L.video(stream({}))
    compare(v.id, "74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20")
    compare(v.title, "No tires tu vieja PC")
    compare(v.kind, "video")
    compare(v.duration, 2701)
    compare(v.released, 1790500000)
    compare(v.sd, "67dc70")
    compare(v.size, 122289526)
    compare(v.tags, ["linux", "windows"])
    compare(v.channel.title, "SrLedwis")
    compare(v.channel.count, 233)
    verify(L.playable(v))
  }

  function test_not_videos() {
    compare(L.video(null), null)
    compare(L.video(chan), null)
    var post = stream({})
    post.value = JSON.parse(JSON.stringify(post.value))
    post.value.stream_type = "document"
    compare(L.video(post), null)
    var nofile = stream({})
    nofile.value = JSON.parse(JSON.stringify(nofile.value))
    delete nofile.value.source
    compare(L.video(nofile), null)
  }

  function test_repost_is_the_original() {
    var v = L.video({ value_type: "repost", reposted_claim: stream({}) })
    compare(v.id, "74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20")
  }

  function test_paid_and_members_do_not_play() {
    var paid = stream({})
    paid.value = JSON.parse(JSON.stringify(paid.value))
    paid.value.fee = { amount: "2", currency: "LBC" }
    verify(!L.playable(L.video(paid)))
    var members = stream({})
    members.value = JSON.parse(JSON.stringify(members.value))
    members.value.tags = ["c:members-only"]
    var m = L.video(members)
    verify(m.members)
    verify(!L.playable(m))
    compare(m.tags, [])
  }

  function test_videos_once_each() {
    var list = L.videos({ items: [stream({}), stream({}), chan, { value_type: "stream" }] })
    compare(list.length, 1)
    compare(L.videos(null), [])
    compare(L.channels({ items: [chan, stream({})] }).length, 1)
  }

  function test_markdown_is_read_as_words() {
    compare(L.plain("### Introduction\nThis is **bold** and [a site](https://x.org) ![pic](https://x/p.png)\n\n\n\n---\nend"),
            "Introduction\nThis is bold and a site (https://x.org)\n\nend")
    compare(L.plain("[https://x.org](https://x.org)"), "https://x.org")
    compare(L.plain(null), "")
  }

  function test_append_skips_what_is_there() {
    var a = [{ id: "1" }, { id: "2" }]
    var b = [{ id: "2" }, { id: "3" }]
    compare(L.append(a, b).map(function (x) { return x.id }), ["1", "2", "3"])
  }

  // --- the wire

  function test_answer() {
    compare(L.result(0, JSON.stringify({ jsonrpc: "2.0", result: { items: [] } }) + "\n200").data.items, [])
    verify(L.result(0, "{}\n429").error.indexOf("rate-limiting") >= 0)
    verify(L.result(0, "<html>\n502").error.indexOf("trouble") >= 0)
    verify(L.result(0, "<html>\n200").error.indexOf("not JSON") >= 0)
    verify(L.result(6, "").error.indexOf("No answer") >= 0)
    verify(L.result(28, "").error.indexOf("too long") >= 0)
    compare(L.result(0, JSON.stringify({ error: { message: "bad params" } }) + "\n200").error, "Odysee: bad params")
  }

  function test_rpc_command() {
    var argv = L.rpc("claim_search", { page: 1 })
    compare(argv[0], "curl")
    compare(argv[argv.length - 1], L.PROXY)
    var body = JSON.parse(argv[argv.indexOf("--data-binary") + 1])
    compare(body.method, "claim_search")
    compare(body.params.page, 1)
  }

  function test_lighthouse() {
    var argv = L.lighthouse("linux desktop", "videos", 2)
    var u = argv[argv.length - 1]
    verify(u.indexOf("s=linux%20desktop") > 0)
    verify(u.indexOf("from=24") > 0)
    verify(u.indexOf("claimType=file") > 0)
    verify(L.lighthouse("x", "channels", 1)[argv.length - 1].indexOf("claimType=channel") > 0)
    var ids = L.hits([{ claimId: "74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20" }, { claimId: "nope" },
                      { claimId: "74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20" }])
    compare(ids, ["74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20"])
    compare(L.inOrder([{ id: "b" }, { id: "a" }], ["a", "b", "c"]).map(function (x) { return x.id }), ["a", "b"])
  }

  function test_feed_params() {
    var cat = { key: "tech", channels: ["affb63e10b2ddc4fbd16520ea7cda3d02f9b982c"], perChannel: 2, days: 10, order: "trending", excluded: [] }
    var p = L.feed(cat, 3, 1000000000)
    compare(p.page, 3)
    compare(p.release_time, ">" + (1000000000 - 10 * 86400))
    compare(p.limit_claims_per_channel, 2)
    compare(p.order_by, ["trending_group", "trending_mixed"])
    compare(p.fee_amount, "<=0")
    verify(p.not_tags.indexOf("mature") >= 0)
    cat.order = "new"
    compare(L.feed(cat, 1, 0).order_by, ["release_time"])
  }

  function test_categories() {
    var id = "affb63e10b2ddc4fbd16520ea7cda3d02f9b982c"
    var data = { data: { en: { categories: [
      { name: "news", label: "News", channelIds: [id], hideByDefault: true, sortOrder: 1 },
      { name: "tech", label: "Tech", channelIds: [id, "junk"], sortOrder: 80, channelLimit: "2", daysOfContent: 180 },
      { name: "featured", label: "Featured", channelIds: [id], sortOrder: 2 },
      { name: "explore", label: "Discover", pinnedClaimIds: [id] },
      { name: "empty", label: "Empty", channelIds: [] }
    ] } } }
    var cats = L.categories(data, "en-US")
    compare(cats.map(function (c) { return c.key }), ["featured", "tech", "news"])
    compare(cats[1].channels, [id])
    compare(cats[1].perChannel, 2)
    compare(cats[1].days, 180)
    compare(L.categories(data, "de").length, 3)
    compare(L.categories({}, "en"), [])
  }

  // --- where things are

  function test_links() {
    var v = L.video(stream({}))
    compare(L.stream(v), "https://player.odycdn.com/v6/streams/74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20/67dc70.mp4")
    compare(L.web(v.url), "https://odysee.com/@SrLedwis:a/no-tires-tu-vieja-pc-windows-11-vs-linux:7")
    compare(L.uri("https://odysee.com/@SrLedwis:a/no-tires:7?r=abc"), "lbry://@SrLedwis#a/no-tires#7")
    compare(L.uri("https://odysee.com/@Odysee:8"), "lbry://@Odysee#8")
    compare(L.uri("lbry://@x#1/y"), "lbry://@x#1/y")
    compare(L.uri("@Odysee"), "lbry://@Odysee")
    compare(L.uri("https://odysee.com/$/settings"), "")
    compare(L.uri("linux"), "")
    compare(L.uri(""), "")
    compare(L.image("https://x/y.png", 390, 220), "https://thumbnails.odycdn.com/card/s:390:220/quality:85/plain/https://x/y.png")
    compare(L.image("", 1, 1), "")
  }

  function test_hls_variants() {
    var v = L.video(stream({}))
    var m = L.master(v)
    compare(m, "https://player.odycdn.com/v6/streams/74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20/67dc70/master.m3u8")
    var body = "#EXTM3U\n#EXT-X-VERSION:6\n"
      + "#EXT-X-STREAM-INF:BANDWIDTH=655600,RESOLUTION=640x360,CODECS=\"avc1\"\nv2.m3u8\n\n"
      + "#EXT-X-STREAM-INF:BANDWIDTH=4026000,RESOLUTION=1920x1080\nv0.m3u8\n"
      + "#EXT-X-STREAM-INF:BANDWIDTH=2890800,RESOLUTION=1280x720\n\nv1.m3u8\n"
      + "#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1080x1920\nhttps://x/portrait.m3u8\n"
    var list = L.variants(body, m)
    compare(list.map(function (x) { return x.label }), ["1080p", "720p", "360p"])
    compare(list[1].url, "https://player.odycdn.com/v6/streams/74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20/67dc70/v1.m3u8")
    compare(L.pick(list, 720).label, "720p")
    compare(L.pick(list, 480).label, "360p")
    compare(L.pick(list, 100).label, "360p")
    compare(L.pick([], 720), null)
    compare(L.variants("This content cannot be accessed", m), [])
    compare(L.clock(3725000), "1:02:05")
    compare(L.clock(65000), "1:05")
    compare(L.clock(-1), "0:00")
  }

  // --- what a person reads

  function test_figures() {
    compare(L.duration(2701), "45:01")
    compare(L.duration(3725), "1:02:05")
    compare(L.duration(59), "0:59")
    compare(L.duration(0), "")
    var now = 1790600000
    compare(L.ago(now - 30, now), "just now")
    compare(L.ago(now - 3600, now), "1 hour ago")
    compare(L.ago(now - 3 * 86400, now), "3 days ago")
    compare(L.ago(now - 14 * 86400, now), "2 weeks ago")
    compare(L.ago(now - 400 * 86400, now), "1 year ago")
    compare(L.ago(0, now), "")
    compare(L.size(122289526), "122 MB")
    compare(L.size(2500000000), "2.5 GB")
    compare(L.count(15320), "15k")
    compare(L.count(1200), "1.2k")
    compare(L.count(2000000), "2M")
    compare(L.resolution({ width: 1920, height: 1080 }), "1080p")
    compare(L.resolution({ width: 3840, height: 2160 }), "4K")
    compare(L.uploadsText({ count: 1 }), "1 upload")
    compare(L.byline({ channel: { title: "A" }, released: now - 7200 }, now), "A · 2 hours ago")
  }

  function test_facts() {
    var f = L.facts(L.video(stream({})))
    var labels = f.map(function (x) { return x.label })
    compare(labels, ["Released", "Length", "Picture", "Size", "Language", "License"])
    compare(f[4].value, "ES")
  }

  // --- the library

  function test_save_toggle() {
    var v = L.video(stream({}))
    var r = L.toggle([], v, 2)
    verify(r.on)
    compare(r.list.length, 1)
    r = L.toggle(r.list, v, 2)
    verify(!r.on)
    compare(r.list.length, 0)
    var full = L.toggle([{ id: "a" }, { id: "b" }], v, 2)
    verify(full.full)
  }

  function test_history_moves_to_top() {
    var a = L.video(stream({}))
    var b = L.video(stream({ claim_id: "1111111111111111111111111111111111111111" }))
    var h = L.played([], a, 10)
    h = L.played(h, b, 20)
    h = L.played(h, a, 30)
    compare(h.map(function (x) { return x.id }), [a.id, b.id])
    compare(h[0].playedAt, 30)
  }

  function test_library_round_trip() {
    var v = L.video(stream({}))
    var ch = v.channel
    var lib = { follows: L.followChannel([], ch).list, saved: [v], history: L.played([], v, 5) }
    var back = L.parseLibrary(JSON.parse(L.serializeLibrary(lib)))
    compare(back.follows.length, 1)
    compare(back.follows[0].title, "SrLedwis")
    compare(back.saved[0].title, v.title)
    compare(back.history[0].playedAt, 5)
  }

  function test_library_ignores_junk() {
    var back = L.parseLibrary({ follows: [{ id: "x" }, null, 3], saved: "no", history: [{ id: "74c9fe05950c5936f09e1d9e3deb1b9da2a4bf20" }] })
    compare(back.follows, [])
    compare(back.saved, [])
    compare(back.history, [])
    compare(L.parseLibrary(null).follows, [])
  }

  function test_homepage_round_trip() {
    var cats = [{ key: "tech", label: "Tech", channels: ["a"], perChannel: 1, days: 30, order: "trending", excluded: [] }]
    var back = L.parseHomepage(JSON.parse(L.serializeHomepage(cats, 123)))
    compare(back.categories.length, 1)
    compare(back.fetched, 123)
    compare(L.parseHomepage({ categories: [{ key: 1 }] }).categories, [])
  }
}
