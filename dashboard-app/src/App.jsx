import React, { useEffect, useState } from "react";

function App() {
  const [loading, setLoading] = useState(true);
  const [dashboardData, setDashboardData] = useState(null);
  const [error, setError] = useState("");

  useEffect(() => {
    const token = localStorage.getItem("token");
    if (!token) {
      setError("Not logged in.");
      setLoading(false);
      return;
    }

    fetch("https://8vkjpgpih5.execute-api.us-east-1.amazonaws.com/prod/dashboard", {
      headers: {
        Authorization: `Bearer ${token}`,
      },
    })
      .then((res) => {
        if (!res.ok) throw new Error("Unauthorized");
        return res.json();
      })
      .then((data) => {
        setDashboardData(data);
        setLoading(false);
      })
      .catch((err) => {
        console.error(err);
        setError("Failed to load dashboard.");
        setLoading(false);
      });
  }, []);

  if (loading) return <p>Loading...</p>;
  if (error) return <p style={{ color: "crimson" }}>{error}</p>;

  return (
    <div style={{ padding: "2rem", fontFamily: "sans-serif" }}>
      <h1>Welcome, {dashboardData.user}</h1>
      <p>Email: {dashboardData.email}</p>
      <p>{dashboardData.content}</p>
    </div>
  );
}

export default App;
