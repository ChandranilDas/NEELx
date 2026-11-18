// Cloudflare Pages Function: POST /api/feedback
// Sends both website & NEELx in-app feedback directly to your email via Brevo's free API (300 emails/day).
// Set these environment variables in Cloudflare Pages -> Settings -> Environment Variables:
//   BREVO_API_KEY   = your Brevo v3 API key
//   FEEDBACK_TO     = chandranildas925@gmail.com
//   FEEDBACK_FROM   = feedback@your-domain.com (verified sender in Brevo / Cloudflare Email Routing)

export async function onRequestPost(context) {
  const { request, env } = context;
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };

  try {
    const body = await request.json();
    const category = String(body.category || "Feedback").slice(0, 60);
    const title = String(body.title || `[${category}] NEELx Beta Feedback`).slice(0, 140);
    const rating = String(body.rating || "N/A").slice(0, 20);
    const macModel = String(body.macModel || "macOS").slice(0, 120);
    const message = String(body.message || "").trim().slice(0, 4000);
    const diagnostics = String(body.diagnostics || "").slice(0, 2500);

    if (!message) {
      return new Response(JSON.stringify({ ok: false, error: "Empty message" }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    if (!env.BREVO_API_KEY) {
      return new Response(
        JSON.stringify({ ok: false, error: "BREVO_API_KEY not configured yet in Cloudflare Pages" }),
        { status: 503, headers: corsHeaders }
      );
    }

    const toEmail = env.FEEDBACK_TO || "chandranildas925@gmail.com";
    const fromEmail = env.FEEDBACK_FROM || toEmail;

    const textContent = [
      `Category: ${category}`,
      `Rating: ${rating}`,
      `Mac: ${macModel}`,
      "",
      "Message:",
      message,
      diagnostics ? `\n${diagnostics}` : "",
    ].join("\n");

    const brevoRes = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: {
        "api-key": env.BREVO_API_KEY,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        sender: { name: "NEELx Feedback", email: fromEmail },
        to: [{ email: toEmail, name: "Chandranil Das" }],
        subject: title,
        textContent,
      }),
    });

    if (!brevoRes.ok) {
      const errText = await brevoRes.text();
      return new Response(JSON.stringify({ ok: false, error: errText }), {
        status: 502,
        headers: corsHeaders,
      });
    }

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: corsHeaders });
  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: String(err) }), {
      status: 500,
      headers: corsHeaders,
    });
  }
}

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    },
  });
}
