require('dotenv').config();
const express = require('express');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;
const PYTHON_VALIDATOR_BASE_URL = process.env.PYTHON_VALIDATOR_BASE_URL;
const API_SECURITY_TOKEN = process.env.API_SECURITY_TOKEN;

if (!PYTHON_VALIDATOR_BASE_URL || !API_SECURITY_TOKEN) {
  // Fail fast, the same discipline as config.py's fix in task 7.4 (T2) —
  // a missing required config value stops the service at start-up rather
  // than silently defaulting somewhere a caller can't see.
  console.error('FATAL: PYTHON_VALIDATOR_BASE_URL and/or API_SECURITY_TOKEN is not set. Exiting.');
  process.exit(1);
}

app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// Simple health check — same shape as the Java/Python services' own,
// so it's inspectable the same way (`curl .../health`).
app.get('/health', (req, res) => {
  res.json({ status: 'UP', pythonValidatorBaseUrl: PYTHON_VALIDATOR_BASE_URL });
});

app.post('/submit', async (req, res) => {
  const { meter_id, grid_zone, timestamp, kwh_value } = req.body;

  const payload = {
    meter_id,
    grid_zone,
    readings: [{ timestamp, kwh_value: Number(kwh_value) }],
  };

  // Talking to python-validator directly (section 0's corrected scope) —
  // not java-gateway. This means the token java-gateway used to attach
  // on Node's behalf must now be attached here instead.
  const targetUrl = `${PYTHON_VALIDATOR_BASE_URL}/api/v1/transform`;
  console.log(`[submit] forwarding to ${targetUrl}:`, JSON.stringify(payload));

  try {
    const upstream = await fetch(targetUrl, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-EAI-TOKEN': API_SECURITY_TOKEN,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10000),
    });

    // python-validator's response is genuine application/json (FastAPI's
    // own serialisation) — unlike the java-gateway passthrough this
    // document originally routed through, there is no D5-style
    // text/plain body to guard against on this path. .json() is safe
    // here specifically because this upstream is Python, not Java.
    const body = await upstream.json();
    console.log(`[submit] upstream responded ${upstream.status}:`, JSON.stringify(body));

    res.status(upstream.status).json({
      upstreamStatus: upstream.status,
      upstreamBody: body,
    });
  } catch (err) {
    if (err.name === 'TimeoutError') {
      console.error('[submit] python-validator did not respond within 10s');
      return res.status(504).json({ error: 'python-validator timed out' });
    }    
    // A network-level failure (upstream unreachable, DNS failure,
    // connection refused) is distinct from an upstream HTTP error
    // response above, and is reported distinctly here — this
    // distinction is exactly what B3's request trace will need to
    // name precisely.
    console.error('[submit] network-level failure reaching python-validator:', err.message);
    res.status(502).json({ error: 'Could not reach python-validator', detail: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`[startup] node-frontend listening on port ${PORT}`);
  console.log(`[startup] PYTHON_VALIDATOR_BASE_URL = ${PYTHON_VALIDATOR_BASE_URL}`);
});