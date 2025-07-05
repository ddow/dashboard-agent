// dashboard-app/src/api.js

const API_BASE_URL = process.env.REACT_APP_API_BASE_URL || window.location.origin;

async function login(email, password) {
  const response = await fetch(`${API_BASE_URL}/login`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ username: email, password }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Login failed: ${errorText}`);
  }

  return response.json();
}

async function getDashboard(token) {
  const response = await fetch(`${API_BASE_URL}/dashboard`, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Load failed: ${errorText}`);
  }

  return response.json();
}

export { login, getDashboard };
