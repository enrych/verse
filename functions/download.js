// GET /download — serves the latest Verse.dmg from Cloudflare.
//
// The first request after a new release fetches the DMG from GitHub once and
// stores it in Workers KV (binding: DOWNLOADS); every later request is served
// from Cloudflare. If anything goes wrong it falls back to GitHub Releases.
const REPO = "enrych/verse";
const ASSET = "Verse.dmg";
const GITHUB = `https://github.com/${REPO}/releases/latest/download/${ASSET}`;

async function latestTag(env) {
  const cached = await env.DOWNLOADS.get("latest-tag");
  if (cached) return cached;
  const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: { "User-Agent": "verse-site", Accept: "application/vnd.github+json" },
  });
  if (!res.ok) return null;
  const { tag_name: tag } = await res.json();
  if (tag) await env.DOWNLOADS.put("latest-tag", tag, { expirationTtl: 600 });
  return tag;
}

export async function onRequestGet({ env, waitUntil }) {
  try {
    if (!env.DOWNLOADS) return Response.redirect(GITHUB, 302);
    const tag = await latestTag(env);
    if (!tag) return Response.redirect(GITHUB, 302);

    const key = `dmg:${tag}`;
    let body = await env.DOWNLOADS.get(key, "arrayBuffer");
    if (!body) {
      const res = await fetch(`https://github.com/${REPO}/releases/download/${tag}/${ASSET}`, { redirect: "follow" });
      if (!res.ok) return Response.redirect(GITHUB, 302);
      body = await res.arrayBuffer();
      waitUntil(env.DOWNLOADS.put(key, body));
    }
    return new Response(body, {
      headers: {
        "Content-Type": "application/x-apple-diskimage",
        "Content-Disposition": `attachment; filename="${ASSET}"`,
        "Content-Length": String(body.byteLength),
        "Cache-Control": "public, max-age=300",
        "X-Verse-Version": tag,
      },
    });
  } catch {
    return Response.redirect(GITHUB, 302);
  }
}
