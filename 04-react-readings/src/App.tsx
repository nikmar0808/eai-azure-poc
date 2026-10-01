import { useState } from 'react';

type Reading = {
  timestamp: string;
  kwh_value: number;
  voltage: number | null;
};

type ReadingsResponse = {
  meter_id: string;
  count: number;
  readings: Reading[];
};

function App() {
  const [meterId, setMeterId] = useState('MTR-NODE-001');
  const [data, setData] = useState<ReadingsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleQuery(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const res = await fetch(`/api/v1/meters/${encodeURIComponent(meterId)}/readings?limit=20`);
      const text = await res.text();
      // Same defensive parsing discipline as B2's index.html — a platform-level
      // error (Front Door, nginx, a timeout) is not guaranteed to be JSON.
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch {
        body = { nonJsonResponse: text, status: res.status };
      }
      if (!res.ok) {
        setError(`Request failed (${res.status}): ${JSON.stringify(body)}`);
        setData(null);
      } else {
        setData(body as ReadingsResponse);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <h1>Smart Meter Readings</h1>
      <form onSubmit={handleQuery}>
        <label>
          Meter ID:{' '}
          <input value={meterId} onChange={(e) => setMeterId(e.target.value)} />
        </label>
        <button type="submit" disabled={loading}>
          {loading ? 'Querying...' : 'Query'}
        </button>
      </form>
      {error && <p style={{ color: 'red' }}>{error}</p>}
      {data && (
        <table>
          <thead>
            <tr><th>Timestamp</th><th>kWh</th><th>Voltage</th></tr>
          </thead>
          <tbody>
            {data.readings.map((r, i) => (
              <tr key={i}>
                <td>{r.timestamp}</td>
                <td>{r.kwh_value}</td>
                <td>{r.voltage ?? '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

export default App;
