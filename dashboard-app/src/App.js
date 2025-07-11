// dashboard-app/src/App.js

import React, { useState } from "react";
import { login, getDashboard } from "./api";

function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState("");
  const [dashboardData, setDashboardData] = useState(null);
  const [error, setError] = useState("");

  const handleLogin = async (e) => {
    e.preventDefault();
    setError("");
    try {
      const result = await login(email, password);
      setToken(result.access_token);
    } catch (err) {
      setError(err.message);
    }
  };

  const loadDashboard = async () => {
    setError("");
    try {
      const data = await getDashboard(token);
      setDashboardData(data);
    } catch (err) {
      setError(err.message);
    }
  };

  const handleLogout = () => {
    setToken("");
    setDashboardData(null);
    setEmail("");
    setPassword("");
  };

  return (
    <div className="App">
      <h1>Daniel & Kristan Dashboard</h1>
      {!token ? (
        <form onSubmit={handleLogin}>
          <h2>Login</h2>
          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          /><br/>
          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          /><br/>
          <button type="submit">Login</button>
          {error && <p style={{ color: "red" }}>{error}</p>}
        </form>
      ) : (
        <div>
          <h2>Dashboard</h2>
          {dashboardData ? (
            <div>
              <p><strong>User:</strong> {dashboardData.user}</p>
              <p><strong>Email:</strong> {dashboardData.email}</p>
              <p>{dashboardData.content}</p>
            </div>
          ) : (
            <p>No dashboard data loaded yet.</p>
          )}
          <button onClick={loadDashboard}>Load Dashboard</button>
          <button onClick={handleLogout}>Log out</button>
          {error && <p style={{ color: "red" }}>{error}</p>}
        </div>
      )}
    </div>
  );
}

export default App;
