// Cloudflare Worker for NEELx
// - Serves the full static NEELx website from ./website via Cloudflare Assets
// - Handles POST /api/feedback from both the website and the NEELx macOS app via Brevo's free API
//
// Required Cloudflare Secret (Workers & Pages -> neelx -> Settings -> Variables and Secrets):
//   BREVO_API_KEY  = your Brevo v3 API key (xkeysib-...)
// Optional Variables (pre-set in wrangler.jsonc):
//   FEEDBACK_TO    = chandranildas925@gmail.com
//   FEEDBACK_FROM  = chandranildas925@gmail.com (or hello@<your-domain> once authenticated in Brevo)

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Accept",
};

function jsonResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...CORS_HEADERS,
      "Content-Type": "application/json",
    },
  });
}

async function handleFeedback(request, env) {
  try {
    const body = await request.json();
    const category = String(body.category || "Feedback").slice(0, 60);
    const title = String(body.title || `[${category}] NEELx Beta Feedback`).slice(0, 140);
    const rating = String(body.rating ?? "N/A").slice(0, 20);
    const macModel = String(body.macModel || "macOS").slice(0, 120);
    const message = String(body.message || "").trim().slice(0, 4000);
    const diagnostics = String(body.diagnostics || "").slice(0, 2500);

    if (!message) {
      return jsonResponse({ ok: false, error: "Empty message" }, 400);
    }

    if (!env.BREVO_API_KEY) {
      return jsonResponse(
        { ok: false, error: "BREVO_API_KEY secret is not added in Cloudflare Worker settings yet." },
        503
      );
    }

    const toEmail = env.FEEDBACK_TO || "chandranildas925@gmail.com";
    const fromEmail = env.FEEDBACK_FROM || toEmail;

    // Sanitize up to 3 optional screenshot attachments (base64-encoded PNG/JPEG/WebP, max ~3.5 MB total)
    const cleanAttachments = [];
    if (Array.isArray(body.attachments)) {
      let totalB64Chars = 0;
      for (const item of body.attachments.slice(0, 3)) {
        if (!item || typeof item.content !== "string") continue;
        const stripped = item.content.replace(/^data:image\/[a-zA-Z0-9.+-]+;base64,/, "").replace(/\s+/g, "");
        if (!stripped || stripped.length > 2_000_000) continue;
        if (totalB64Chars + stripped.length > 4_800_000) break;
        totalB64Chars += stripped.length;
        const rawName = String(item.name || `screenshot-${cleanAttachments.length + 1}.jpg`)
          .replace(/[^a-zA-Z0-9._-]/g, "_")
          .slice(0, 80);
        const safeName = /\.(png|jpe?g|webp|gif)$/i.test(rawName) ? rawName : `${rawName}.jpg`;
        cleanAttachments.push({ name: safeName, content: stripped });
      }
    }

    const textContent = [
      `Category: ${category}`,
      `Rating: ${rating}`,
      `Mac: ${macModel}`,
      cleanAttachments.length > 0 ? `Screenshots attached: ${cleanAttachments.length}` : "",
      "",
      "Message:",
      message,
      diagnostics ? `\n${diagnostics}` : "",
    ]
      .filter((line) => line !== undefined)
      .join("\n");

    const brevoPayload = {
      sender: { name: "NEELx Feedback", email: fromEmail },
      to: [{ email: toEmail, name: "Chandranil Das" }],
      subject: title,
      textContent,
    };
    if (cleanAttachments.length > 0) {
      brevoPayload.attachment = cleanAttachments;
    }

    const brevoRes = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "api-key": env.BREVO_API_KEY,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(brevoPayload),
    });

    if (!brevoRes.ok) {
      const errText = await brevoRes.text();
      return jsonResponse({ ok: false, error: errText }, 502);
    }

    return jsonResponse({ ok: true }, 200);
  } catch (err) {
    return jsonResponse({ ok: false, error: String(err) }, 500);
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/feedback") {
      if (request.method === "OPTIONS") {
        return new Response(null, { status: 204, headers: CORS_HEADERS });
      }
      if (request.method === "POST") {
        return handleFeedback(request, env);
      }
      return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
    }

    if (url.pathname === "/api/health") {
      return jsonResponse({
        ok: true,
        service: "neelx-worker",
        brevoConfigured: Boolean(env.BREVO_API_KEY),
      });
    }

    // Serve the static NEELx website from ./website
    return env.ASSETS.fetch(request);
  },
};
