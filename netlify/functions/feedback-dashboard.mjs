const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store, max-age=0',
    'x-content-type-options': 'nosniff'
  }
});

function nextPageUrl(response) {
  const link = response.headers.get('link') || '';
  const next = link.split(',').map((part) => part.trim()).find((part) => /rel="?next"?/i.test(part));
  const match = next && next.match(/<([^>]+)>/);
  return match ? match[1] : '';
}

async function isFeedbackSubmission(formId, submissionId, apiHeaders, base) {
  let url = `${base}/forms/${encodeURIComponent(formId)}/submissions?per_page=100&page=1`;
  let pageCount = 0;
  while (url && pageCount < 50) {
    const response = await fetch(url, { headers: apiHeaders, signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw new Error(`Netlify submissions lookup failed (${response.status}).`);
    const page = await response.json();
    if (Array.isArray(page) && page.some((item) => String(item.id) === submissionId)) return true;
    pageCount += 1;
    url = nextPageUrl(response);
  }
  return false;
}

export default async (request) => {
  if (!['GET', 'DELETE'].includes(request.method)) return json({ error: 'Method not allowed.' }, 405);

  const auth = request.headers.get('authorization') || '';
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return json({ error: 'Please sign in to view organizer feedback.' }, 401);

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_ANON_KEY;
  const netlifyToken = process.env.NETLIFY_AUTH_TOKEN;
  const siteId = process.env.NETLIFY_SITE_ID;
  const allowedEmails = (process.env.COURTFLOW_FEEDBACK_ADMIN_EMAILS || '').split(',').map((value) => value.trim().toLowerCase()).filter(Boolean);
  if (!supabaseUrl || !supabaseKey || !netlifyToken || !siteId || !allowedEmails.length) {
    console.error('[feedback-dashboard] Missing required environment configuration.');
    return json({ error: 'Feedback dashboard is not configured yet. Ask the Netlify site administrator to complete the setup.' }, 503);
  }

  // Validate the signed-in CourtFlow account with Supabase before exposing or deleting feedback.
  const userResponse = await fetch(`${supabaseUrl.replace(/\/$/, '')}/auth/v1/user`, {
    headers: { apikey: supabaseKey, authorization: `Bearer ${match[1]}` },
    signal: AbortSignal.timeout(10000)
  }).catch(() => null);
  if (!userResponse || !userResponse.ok) return json({ error: 'Your sign-in has expired. Please sign in again.' }, 401);
  const user = await userResponse.json();
  if (!user.email || !allowedEmails.includes(String(user.email).toLowerCase())) {
    return json({ error: 'This CourtFlow account is not authorized to manage organizer feedback.' }, 403);
  }

  const apiHeaders = { authorization: `Bearer ${netlifyToken}`, accept: 'application/json' };
  const base = 'https://api.netlify.com/api/v1';
  try {
    const formsResponse = await fetch(`${base}/sites/${encodeURIComponent(siteId)}/forms`, {
      headers: apiHeaders,
      signal: AbortSignal.timeout(15000)
    });
    if (!formsResponse.ok) throw new Error(`Netlify forms lookup failed (${formsResponse.status}).`);
    const forms = await formsResponse.json();
    const form = Array.isArray(forms) ? forms.find((item) => item.name === 'cf-session-feedback') : null;
    if (!form) {
      if (request.method === 'DELETE') return json({ error: 'The CourtFlow feedback form was not found. Nothing was deleted.' }, 404);
      return json({ submissions: [], formFound: false, message: 'The feedback form has not been detected by Netlify yet. Enable form detection and redeploy CourtFlow.' });
    }

    if (request.method === 'DELETE') {
      let body;
      try { body = await request.json(); } catch { return json({ error: 'A valid feedback submission ID is required.' }, 400); }
      const submissionId = String(body && body.id || '').trim();
      if (!submissionId || submissionId.length > 256 || /[\s/?#]/.test(submissionId)) {
        return json({ error: 'A valid feedback submission ID is required.' }, 400);
      }

      // Restrict deletion to IDs currently listed under this exact form.
      const belongsToFeedbackForm = await isFeedbackSubmission(form.id, submissionId, apiHeaders, base);
      if (!belongsToFeedbackForm) return json({ error: 'That submission is not part of the CourtFlow feedback form, or it has already been deleted.' }, 404);

      const deleteResponse = await fetch(`${base}/submissions/${encodeURIComponent(submissionId)}`, {
        method: 'DELETE',
        headers: apiHeaders,
        signal: AbortSignal.timeout(15000)
      });
      if (!deleteResponse.ok && deleteResponse.status !== 204) {
        throw new Error(`Netlify could not delete this feedback submission (${deleteResponse.status}).`);
      }
      return json({ deleted: true, id: submissionId });
    }

    let url = `${base}/forms/${encodeURIComponent(form.id)}/submissions?per_page=100&page=1`;
    const submissions = [];
    let pageCount = 0;
    while (url && pageCount < 50) {
      const response = await fetch(url, { headers: apiHeaders, signal: AbortSignal.timeout(15000) });
      if (!response.ok) throw new Error(`Netlify submissions lookup failed (${response.status}).`);
      const page = await response.json();
      if (Array.isArray(page)) submissions.push(...page);
      pageCount += 1;
      url = nextPageUrl(response);
    }

    submissions.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
    return json({
      formFound: true,
      submissions: submissions.map((item) => ({ id: item.id, number: item.number, created_at: item.created_at, data: item.data || {} }))
    });
  } catch (error) {
    console.error('[feedback-dashboard]', error);
    return json({ error: 'Could not manage feedback on Netlify. Check the Netlify API token, site ID, and function logs.' }, 502);
  }
};
