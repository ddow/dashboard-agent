// dashboard-app/src/api.js

const API_BASE_URL =
  process.env.REACT_APP_API_URL ||
  "https://8d2wdfciz5.execute-api.us-east-1.amazonaws.com/prod"; // <-- Update if API changes

export async function login(email, password) {
  const response = await fetch(`${API_BASE_URL}/login`, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      username: email,
      password: password,
    }),
  });
  if (!response.ok) {
    throw new Error("Login failed: " + response.statusText);
  }
  return response.json();
}

export async function getDashboard(token) {
  const response = await fetch(`${API_BASE_URL}/dashboard`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });
  if (!response.ok) {
    throw new Error("Load failed: " + response.statusText);
  }
  return response.json();
}
