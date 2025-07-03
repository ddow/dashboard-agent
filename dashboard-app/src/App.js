import React, { useState } from "react";
import { login, fetchDashboard } from "./api";

function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState(localStorage.getItem("token"));
  const [dashboard, setDashboard] = useState(null);
  const [error, setError] = useState("");

  const handleLogin = async () => {
    try {
      const data = await login(email, password);
      localStorage.setItem("token", data.access_token);
      setToken(data.access_token);
      setError("");
    } catch {
      setError("Invalid credentials");
    }
  };

  const loadDashboard = async () => {
    try {
      const data = await fetchDashboard(token);
      setDashboard(data);
    } catch {
      setError("Failed to load dashboard");
    }
  };

  if (!token) {
    return (
      <div>
        <h2>Login</h2>
        <input placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} />
        <input placeholder="Password" type="password" value={password} onChange={e => setPassword(e.target.value)} />
        <button onClick={handleLogin}>Login</button>
        {error && <p>{error}</p>}
      </div>
    );
  }

  return (
    <div>
      <h2>Dashboard</h2>
      <button onClick={loadDashboard}>Load Dashboard</button> {/* 👈 Add this */}
      {dashboard ? (
        <pre>{JSON.stringify(dashboard, null, 2)}</pre>
      ) : (
        <p>No dashboard loaded yet.</p>
      )}
      {error && <p>{error}</p>}
    </div>
  );
}

export default App;
