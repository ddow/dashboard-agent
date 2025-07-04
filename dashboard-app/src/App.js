import React, { useState } from "react";
import axios from "./api";

function App() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState(localStorage.getItem("token") || "");
  const [dashboard, setDashboard] = useState(null);
  const [error, setError] = useState("");

  const handleLogin = async (e) => {
    e.preventDefault();
    setError("");
    try {
      const response = await axios.post("/login", new URLSearchParams({
        username: email,
        password: password,
      }));
      const jwt = response.data.access_token;
      setToken(jwt);
      localStorage.setItem("token", jwt);
      loadDashboard(jwt);
    } catch (err) {
      console.error(err);
      setError("Invalid email or password");
    }
  };

  const loadDashboard = async (jwt) => {
    try {
      const response = await axios.get("/dashboard", {
        headers: { Authorization: `Bearer ${jwt || token}` },
      });
      setDashboard(response.data);
    } catch (err) {
      console.error(err);
      setError("Failed to load dashboard content.");
    }
  };

  const handleLogout = () => {
    setToken("");
    setDashboard(null);
    localStorage.removeItem("token");
  };

  return (
    <div style={{ padding: "2rem", fontFamily: "Arial, sans-serif" }}>
      <h1>Daniel & Kristan Dashboard</h1>

      {!token ? (
        <form onSubmit={handleLogin}>
          <div>
            <label>Email: </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div style={{ marginTop: "1rem" }}>
            <label>Password: </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
            />
          </div>
          <button type="submit" style={{ marginTop: "1rem" }}>
            Login
          </button>
          {error && <p style={{ color: "red" }}>{error}</p>}
        </form>
      ) : (
        <div>
          <p>✅ Logged in</p>
          <button onClick={() => loadDashboard(token)}>Load Dashboard</button>
          <button onClick={handleLogout} style={{ marginLeft: "1rem" }}>
            Logout
          </button>
        </div>
      )}

      {dashboard && (
        <div style={{ marginTop: "2rem", border: "1px solid #ccc", padding: "1rem" }}>
          <h2>Welcome, {dashboard.user}</h2>
          <p>{dashboard.content}</p>
        </div>
      )}
    </div>
  );
}

export default App;
